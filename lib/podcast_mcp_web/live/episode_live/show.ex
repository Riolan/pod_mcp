defmodule PodcastMcpWeb.EpisodeLive.Show do
  use PodcastMcpWeb, :live_view

  alias PodcastMcp.Podcasts # Your Ecto context for podcasts and episodes
  alias PodcastMcp.Podcasts.Episode # Your Episode Ecto schema
  alias Timex # date formatting library

  @impl true
  def mount(%{"id" => episode_id, "podcast_id" => _podcast_id} = _params, _session, socket) do
    # The on_mount hook from your router's live_session (:require_authenticated_user)
    # should have already loaded the current_user if needed.
    # We might not need current_user directly here unless for authorization checks.

    # Fetch the episode by its ID.
    # get_episode!/1 will raise Ecto.NoResultsError if not found,
    # which will result in a 404 error page (standard Phoenix behavior).
    # If you want to handle "not found" differently, use Podcasts.get_episode(episode_id)
    # and pattern match on {:ok, episode} | :error or episode | nil.
    episode = Podcasts.get_episode!(episode_id)

    # Preload associations if you plan to display them and they are not loaded by default
    # For example, if you want to show the podcast title or user email:
    # episode =
    #   episode
    #   |> PodcastMcp.Repo.preload(:podcast)
    #   |> PodcastMcp.Repo.preload(:user) # Assuming you have Repo aliased

    socket =
      socket
      |> assign(:page_title, episode.title || "Show Episode") # For the <.live_title>
      |> assign(:episode, episode)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""

    <.header>
      Episode: <%= @episode.title %>
      <:subtitle>
        <%!-- You might want to show the podcast title here if available --%>
        <%!-- Example: Part of Podcast: <%= @episode.podcast.title %> --%>
        Uploaded on <%= @episode.inserted_at |> Timex.format!("{Mfull} {D}, {YYYY}") %>
      </:subtitle>
    </.header>

    <div class="mt-6 space-y-4">
      <div>
        <h3 class="text-lg font-medium text-gray-900">Episode Details</h3>
        <dl class="mt-2 border-t border-b border-gray-200 divide-y divide-gray-200">
          <div class="py-3 flex justify-between text-sm font-medium">
            <dt class="text-gray-500">Title</dt>
            <dd class="text-gray-900"><%= @episode.title %></dd>
          </div>
          <div class="py-3 flex justify-between text-sm font-medium">
            <dt class="text-gray-500">Status</dt>
            <dd class="text-gray-900 capitalize"><%= @episode.processing_status %></dd>
          </div>
          <div class="py-3 flex justify-between text-sm font-medium">
            <dt class="text-gray-500">Original Audio URL (MinIO)</dt>
            <dd class="text-gray-900 break-all">
              <.link href={@episode.original_audio_url} target="_blank" rel="noopener noreferrer">
                <%= @episode.original_audio_url %>
              </.link>
            </dd>
          </div>
          <div class="py-3 flex justify-between text-sm font-medium">
            <dt class="text-gray-500">Uploaded At</dt>
            <dd class="text-gray-900"><%= @episode.inserted_at %></dd>
          </div>
        </dl>
      </div>

      <%!-- Placeholder for Audio Player --%>
      <%= if @episode.original_audio_url do %>
        <div class="mt-6">
          <h3 class="text-lg font-medium text-gray-900">Listen</h3>
          <audio controls class="w-full mt-2" src={@episode.original_audio_url}>
            Your browser does not support the audio element.
          </audio>
        </div>
      <% end %>

      <%!-- Placeholder for Transcript and Summary (to be added later) --%>
      <%= if @episode.transcript_url do %>
        <div class="mt-6">
          <h3 class="text-lg font-medium text-gray-900">Transcript</h3>
          <%!-- Logic to display transcript --%>
          <p class="text-gray-700">Transcript will be shown here. Link: <.link href={@episode.transcript_url}><%= @episode.transcript_url %></.link></p>
        </div>
      <% end %>

      <%= if @episode.generated_summary do %>
        <div class="mt-6">
          <h3 class="text-lg font-medium text-gray-900">AI Summary</h3>
          <p class="text-gray-700 whitespace-pre-wrap"><%= @episode.generated_summary %></p>
        </div>
      <% end %>

      <div class="mt-8">
        <%!-- Link back to podcast's episode list or all podcasts --%>
        <%!-- <.link navigate={~p"/podcasts/#{@episode.podcast_id}/episodes"}>Back to Episodes</.link> --%>
        <.link navigate={~p"/episodes/new"}>Upload Another Episode</.link>
      </div>
    </div>
    """
  end
end
