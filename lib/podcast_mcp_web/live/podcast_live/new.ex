# lib/podcast_mcp_web/live/podcast_live/new.ex
defmodule PodcastMcpWeb.PodcastLive.New do
  use PodcastMcpWeb, :live_view

  alias PodcastMcp.Podcasts
  alias PodcastMcp.Podcasts.Podcast
  # Assuming your UserAuth on_mount hook assigns :current_user or :current_scope
  alias PodcastMcp.Accounts.User # Ensure this is aliased if current_user is a User struct

  @impl true
  def mount(_params, _session, socket) do
    # The :require_authenticated on_mount hook should ensure current_user is available.
    # Let's retrieve it assuming it's assigned as :current_user or within :current_scope.
    current_user =
      cond do
        socket.assigns[:current_user] -> socket.assigns.current_user
        socket.assigns[:current_scope] && socket.assigns.current_scope.user -> socket.assigns.current_scope.user
        true -> nil # Should have been redirected by :require_authenticated if nil
      end

      if is_nil(current_user) do
        # This should ideally not happen if route is protected.
        # Consider a redirect or error if critical.
        # For now, we'll let it proceed but podcast_options will be empty.
        IO.puts("Warning: current_user is nil in mount of PodcastLive.New")
      end

    # If, for some reason, current_user is nil here despite protections,
    # it's an issue with the auth flow or on_mount hooks.
    # For now, we proceed assuming it's populated.
    # The handle_event("save", ...) will perform a more critical check.

    changeset = Podcasts.change_podcast(%Podcast{}) # <<< --- CORRECTED LINE

    socket =
      socket
      |> assign(:page_title, "Create New Podcast")
      |> assign(:form, to_form(changeset))
      |> assign_new(:current_user, fn -> current_user end) # Ensure current_user is consistently assigned

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""

    <.header>
      Create New Podcast
      <:subtitle>Fill in the details for your new podcast series.</:subtitle>
    </.header>

    <.form
      for={@form}
      id="podcast-new-form"
      phx-change="validate"
      phx-submit="save"
    >
      <.input field={@form[:title]} type="text" label="Podcast Title" required />
      <.input field={@form[:description]} type="textarea" label="Description" required />
      <.input field={@form[:cover_art_url]} type="url" label="Cover Art URL" placeholder="https://example.com/image.png" />

      <div class="mt-6">
        <.button type="submit" phx-disable-with="Saving...">Create Podcast</.button>
      </div>
    </.form>

    <div class="mt-4">
      <%!-- Eventually, link to a page showing all user's podcasts --%>
      <%!-- <.link navigate={~p"/podcasts"}>Back to My Podcasts</.link> --%>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"podcast" => podcast_params}, socket) do
    # The current_user is needed if your Podcast.changeset/2 relies on it
    # or if you were to use Podcast.changeset/3 with a scope.
    # For now, assuming Podcast.changeset/2 just takes attrs.
    changeset =
      %Podcast{}
      |> Podcasts.change_podcast(podcast_params) # Uses the change_podcast/2 from context
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"podcast" => podcast_params}, socket) do
    current_user = socket.assigns.current_user # Should be populated from mount

    if is_nil(current_user) do
      # This should ideally be caught by route protection / on_mount hooks
      {:noreply, put_flash(socket, :error, "Authentication error. Please log in again.")}
    else
      # Add the current user's ID to the parameters for podcast creation
      attrs_with_user = Map.put(podcast_params, "user_id", current_user.id)

      case Podcasts.create_podcast(attrs_with_user) do
        {:ok, podcast} ->
          {:noreply,
           socket
           |> put_flash(:info, "Podcast '#{podcast.title}' created successfully!")
           # Redirect to a page showing the new podcast or a list of podcasts.
           # We'll need to create a PodcastLive.Show or PodcastLive.Index later.
           # For now, redirecting to the new episode page for this podcast might be a placeholder,
           # or back to the podcast creation page with a success message.
           # Let's redirect to where they can upload an episode for this new podcast.
           |> push_navigate(to: ~p"/episodes/new")} # Or ~p"/podcasts/#{podcast.id}" if you create podcast show page

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end
end
