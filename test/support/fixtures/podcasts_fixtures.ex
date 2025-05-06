defmodule PodcastMcp.PodcastsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PodcastMcp.Podcasts` context.
  """

  @doc """
  Generate a episode.
  """
  def episode_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        generated_summary: "some generated_summary",
        generated_timestamps: %{},
        original_audio_url: "some original_audio_url",
        processing_status: "some processing_status",
        title: "some title",
        transcript_url: "some transcript_url"
      })

    {:ok, episode} = PodcastMcp.Podcasts.create_episode(scope, attrs)
    episode
  end

  @doc """
  Generate a podcast.
  """
  def podcast_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        cover_art_url: "some cover_art_url",
        description: "some description",
        title: "some title"
      })

    {:ok, podcast} = PodcastMcp.Podcasts.create_podcast(scope, attrs)
    podcast
  end
end
