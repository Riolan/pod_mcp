# lib/podcast_mcp_web/live/episode_live/new.ex
defmodule PodcastMcpWeb.EpisodeLive.New do
  use PodcastMcpWeb, :live_view

  alias PodcastMcp.Podcasts
  alias PodcastMcp.Podcasts.Episode
  alias ExAws.S3 # For S3 operations
  alias MIME # For MIME type detection
  # Assuming phx.gen.auth setup includes an on_mount hook like UserAuth.fetch_current_user
  # which assigns `:current_user` to the socket if logged in.

  @impl true
  def mount(_params, _session, socket) do
    # We assume current_user is assigned by an :on_mount hook from phx.gen.auth
    # If not assigned, the route protection should have already redirected.

    changeset = Podcasts.change_episode(%Episode{})

    socket =
      socket
      |> assign(:form, to_form(changeset))
      |> allow_upload(:audio,
        accept: ~w(.mp3 .wav .m4a .ogg .aac), # Or other formats you want
        max_entries: 1,
        max_file_size: 500 * 1024 * 1024, # 500MB limit - adjust as needed
        auto_upload: true
      )

    {:ok, socket}


  end
  @impl true
  def render(assigns) do
    # Add safe debugging checks to avoid errors
    audio_uploads = Map.get(assigns, :uploads, %{}) |> Map.get(:audio)

    if audio_uploads do
      IO.inspect(audio_uploads, label: "@uploads.audio in render")
      IO.inspect(Map.get(assigns.form || %{}, :audio), label: "@form[:audio] (FormField) in render")
    end

    ~H"""
    <.header>
      Upload New Episode
      <:subtitle>Select your audio file and give it a title.</:subtitle>
    </.header>
    <.form
      for={@form}
      id="episode-upload-form"
      phx-change="validate"
      phx-submit="save"
      >
      <.input field={@form[:title]} type="text" label="Episode Title" required />


      <div class="mt-4">
        <.live_file_input upload={@uploads.audio} class="hidden" />
        <div class="py-4 px-6 bg-gray-100 rounded cursor-pointer text-center" phx-click={JS.dispatch("click", to: "##{@uploads.audio.ref}")}>
          <div class="text-sm font-medium">Click or drag files here</div>
          <div class="text-xs text-gray-500">MP3, WAV, M4A, OGG, AAC (max 500MB)</div>
        </div>
      </div>

      <%= if assigns[:uploads] && assigns.uploads[:audio] && assigns.uploads.audio.entries do %>
        <div :for={entry <- assigns.uploads.audio.entries}>
          <.live_file_input upload={@uploads.audio} entry_ref={entry.ref} class="hidden"/>
          <p>
            <%= entry.client_name %> (<%= div(entry.progress, 1) %>%)
          </p>
          <%= for err <- upload_errors(@uploads.audio, entry) do %>
            <p class="text-red-600"><%= error_to_string(err) %></p>
          <% end %>
          <progress value={entry.progress} max="100" class="w-full"> <%= entry.progress %>% </progress>
        </div>
      <% end %>

      <%= if assigns[:uploads] && assigns.uploads[:audio] do %>
        <%= for err <- upload_errors(@uploads.audio) do %>
          <p class="text-red-600"><%= error_to_string(err) %></p>
        <% end %>
      <% end %>

      <div class="mt-6">
        <.button type="submit" phx-disable-with="Uploading...">
          Upload Episode
        </.button>
      </div>
    </.form>
    """
  end
  # --- Event Handlers ---

  @impl true
  def handle_event("validate", %{"episode" => episode_params}, socket) do
    # Basic validation on title field, ignore audio field here
    changeset =
      %Episode{} # Start with an empty struct
      |> Podcasts.change_episode(episode_params)
      |> Map.put(:action, :validate) # Important for changeset error display

    {:noreply, assign(socket, :form, to_form(changeset))}
  end


  # lib/podcast_mcp_web/live/episode_live/new.ex
  @impl true
  def handle_event("save", %{"episode" => episode_params}, socket) do
    current_scope = socket.assigns.current_scope
    current_user = if current_scope, do: current_scope.user, else: nil

    if is_nil(current_user) do
      IO.inspect("Access Denied: current_user is nil in handle_event/save")
      {:noreply, put_flash(socket, :error, "You must be logged in to upload.")}
    else
      # consume_uploaded_entries will now attempt the S3 upload internally
      # and return richer information or an error.
      uploaded_file_results =
        consume_uploaded_entries(socket, :audio, fn meta, entry ->
          # S3 Upload logic is now INSIDE this callback
          temp_path = meta.path # Path to the temporary file on the server
          original_name = entry.client_name

          bucket = System.get_env("MINIO_BUCKET") || "podcast-episodes"
          extension = Path.extname(original_name)
          unique_filename = "#{Ecto.UUID.generate()}#{extension}"
          object_key = "episodes/#{current_user.id}/#{unique_filename}" # current_user is in lexical scope
          content_type = MIME.from_path(original_name) || "application/octet-stream"

          # Perform the S3 stream upload
          case temp_path
               |> ExAws.S3.Upload.stream_file() # File at temp_path exists here
               |> ExAws.S3.upload(bucket, object_key, content_type: content_type)
               |> ExAws.request() do
            {:ok, _s3_response} ->
              # S3 Upload Successful!
              minio_scheme = System.get_env("MINIO_SCHEME") || "http"
              minio_host = System.get_env("MINIO_HOST") || "localhost"
              minio_port = System.get_env("MINIO_PORT") || "9000"
              minio_url = "#{minio_scheme}://#{minio_host}:#{minio_port}/#{bucket}/#{object_key}"

              # The temporary file (temp_path) will be cleaned up by LiveView
              # automatically because we are returning {:ok, ...} from this callback.
              # No need for File.rm(temp_path) manually for this.
              {:ok, %{minio_url: minio_url, object_key: object_key, original_name: original_name}}

            {:error, {status_code, s3_error_body}} ->
              IO.inspect(s3_error_body, label: "S3 Upload HTTP Error inside consume #{status_code}")
              {:error, {:s3_http_error, status_code}} # Propagate a structured error

            {:error, s3_reason} ->
              IO.inspect(s3_reason, label: "S3 Upload Error inside consume")
              {:error, {:s3_error, s3_reason}} # Propagate a structured error
          end
        end)

      # Now process the results from consume_uploaded_entries
      case uploaded_file_results do
        [] ->
          # No file was selected or consumed properly (e.g., if consume_uploaded_entries itself had an issue before calling the callback)
          # Or if an error was returned by the callback, it might appear here depending on LiveView version or if you map errors.
          # For required validation, it's better to check before consume or based on `socket.assigns.uploads.audio.entries`.

          # Check if a file was even attempted to be uploaded
          if Enum.empty?(socket.assigns.uploads.audio.entries) do
            original_changeset = socket.assigns.form.source
            updated_changeset_with_error =
              Ecto.Changeset.add_error(original_changeset, :audio, "can't be blank", validation: :required)
            {:noreply,
             socket
             |> put_flash(:error, "Please select an audio file.")
             |> assign(:form, to_form(updated_changeset_with_error))}
          else
            # An upload was attempted but failed during the S3 process within consume_uploaded_entries
            # The flash message from that error path should already be set by how you handle the error tuple below.
            # For now, just a generic message, but specific errors are better.
            {:noreply, put_flash(socket, :error, "Failed to process the uploaded file.")}
          end


      # Since max_entries: 1, we expect a list with one result (or an error that led to an empty list handled above)
        [%{minio_url: minio_url, object_key: _object_key, original_name: _original_name} | _] ->
          # S3 Upload was successful, proceed to save to database

          # --- CRITICAL: How to get podcast_id? ---
          # This is a placeholder and NEEDS to be implemented or decided upon.
          podcast_id_to_assign = 1 # TEMPORARY - REPLACE WITH REAL LOGIC

          episode_attrs = %{
            "title" => episode_params["title"], # From the form
            "original_audio_url" => minio_url,
            "processing_status" => "uploaded", # Initial status
            "user_id" => current_user.id,
            "podcast_id" => podcast_id_to_assign # MUST be a valid ID of an existing podcast
          }

          case Podcasts.create_episode(episode_attrs) do
            {:ok, episode} ->
              # No need to File.rm(temp_path) here, LiveView already did it.
              {:noreply,
               socket
               |> put_flash(:info, "Episode '#{episode.title}' uploaded successfully!")
               |> push_navigate(to: ~p"/podcasts/#{episode.podcast_id}/episodes/#{episode.id}")} # Example route

            {:error, %Ecto.Changeset{} = changeset} ->
              IO.inspect(changeset, label: "DB Create Episode Error")
              # File is in MinIO. You might want to implement a cleanup for the S3 object here (advanced).
              {:noreply,
               socket
               |> assign(:form, to_form(Map.put(changeset, :data, %Episode{podcast_id: podcast_id_to_assign}))) # Preserve podcast_id for form
               |> put_flash(:error, "Episode metadata could not be saved. Please check errors.")}
          end

        # Handling errors propagated from the consume_uploaded_entries callback
        [{:error, {:s3_http_error, status_code}} | _] ->
          {:noreply, put_flash(socket, :error, "Failed to upload file to storage. HTTP Status: #{status_code}")}

        [{:error, {:s3_error, _reason}} | _] ->
          {:noreply, put_flash(socket, :error, "Failed to upload file to storage due to an S3 error.")}

        # Catch-all for other unexpected outcomes from consume_uploaded_entries
        _other_results ->
          IO.inspect(_other_results, label: "Unexpected result from consume_uploaded_entries")
          {:noreply, put_flash(socket, :error, "An unexpected error occurred during file processing.")}
      end
    end
  end

  # --- Helper Functions ---

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(:too_many_files), do: "Only one file allowed"
  defp error_to_string(err), do: "Error: #{inspect(err)}"

  # Optional progress handler (can be added to simple_form `upload_progress` attr if needed)
  # defp upload_progress(entry, bytes_uploaded, total_bytes) do
  #   Phoenix.PubSub.broadcast(PodcastMcp.PubSub, "upload_progress:#{entry.uuid}", entry.progress)
  #   :ok
  # end
end
