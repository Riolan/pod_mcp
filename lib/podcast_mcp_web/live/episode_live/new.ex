# lib/podcast_mcp_web/live/episode_live/new.ex
defmodule PodcastMcpWeb.EpisodeLive.New do
  use PodcastMcpWeb, :live_view

  alias PodcastMcp.Podcasts
  alias PodcastMcp.Podcasts.Episode
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

      <.input
        field={@form[:audio]}
        type="file"
        label="Audio File"
        required
      />

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

  @impl true
  def handle_event("save", %{"episode" => episode_params}, socket) do
    # ** IMPLEMENTATION PENDING **
    # This is where the core logic will go:
    # 1. Get current_user from assigns (assuming assigned in mount/on_mount)
    #    user = socket.assigns.current_user
    # 2. Determine the target podcast_id for this user.
    #    - Does the user already have a podcast? Get its ID.
    #    - If not, do we create one? Or show an error? (Requires more logic in Podcasts context)
    #    - For now, we might hardcode/fetch a default podcast ID if known, or defer this part.
    #    podcast_id = get_users_podcast_id(user) # Placeholder for needed logic
    # 3. Consume the uploaded file entry from @uploads.audio
    #    uploaded_files = consume_uploaded_entries(socket, :audio, fn %{path: path}, _entry -> ... end)
    # 4. Inside the consume_uploaded_entries callback:
    #    - Stream/Upload the file at `path` to MinIO using ExAws.S3 or Waffle.
    #    - Get the MinIO object URL/key upon successful upload.
    #    - Return {:ok, minio_url} from the callback.
    # 5. If MinIO upload is successful (consume_uploaded_entries returns the list of {:ok, minio_url} tuples):
    #    - Add the podcast_id and original_audio_url (from MinIO) to episode_params.
    #    - Set initial processing_status (e.g., "uploaded").
    #    - Call the context function to save the episode:
    #      case Podcasts.create_episode(user, Map.put(episode_params, "original_audio_url", minio_url)) do
    #        {:ok, episode} -> redirect(socket, to: ~p"/episodes/#{episode.id}") # Redirect to episode page (to be created)
    #        {:error, changeset} -> re-render form with errors
    #      end
    # 6. Handle errors from file consumption or database saving.

    IO.inspect(episode_params, label: "Episode Params on Save (raw)")
    IO.inspect(socket.assigns.uploads.audio, label: "Uploads Status")

    {:noreply,
     socket
     |> put_flash(:info, "Save action triggered - MinIO/DB logic not yet implemented.")}
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
