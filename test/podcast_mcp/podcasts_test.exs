defmodule PodcastMcp.PodcastsTest do
  use PodcastMcp.DataCase

  alias PodcastMcp.Podcasts

  describe "episodes" do
    alias PodcastMcp.Podcasts.Episode

    import PodcastMcp.AccountsFixtures, only: [user_scope_fixture: 0]
    import PodcastMcp.PodcastsFixtures

    @invalid_attrs %{title: nil, original_audio_url: nil, processing_status: nil, transcript_url: nil, generated_summary: nil, generated_timestamps: nil}

    test "list_episodes/1 returns all scoped episodes" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      episode = episode_fixture(scope)
      other_episode = episode_fixture(other_scope)
      assert Podcasts.list_episodes(scope) == [episode]
      assert Podcasts.list_episodes(other_scope) == [other_episode]
    end

    test "get_episode!/2 returns the episode with given id" do
      scope = user_scope_fixture()
      episode = episode_fixture(scope)
      other_scope = user_scope_fixture()
      assert Podcasts.get_episode!(scope, episode.id) == episode
      assert_raise Ecto.NoResultsError, fn -> Podcasts.get_episode!(other_scope, episode.id) end
    end

    test "create_episode/2 with valid data creates a episode" do
      valid_attrs = %{title: "some title", original_audio_url: "some original_audio_url", processing_status: "some processing_status", transcript_url: "some transcript_url", generated_summary: "some generated_summary", generated_timestamps: %{}}
      scope = user_scope_fixture()

      assert {:ok, %Episode{} = episode} = Podcasts.create_episode(scope, valid_attrs)
      assert episode.title == "some title"
      assert episode.original_audio_url == "some original_audio_url"
      assert episode.processing_status == "some processing_status"
      assert episode.transcript_url == "some transcript_url"
      assert episode.generated_summary == "some generated_summary"
      assert episode.generated_timestamps == %{}
      assert episode.user_id == scope.user.id
    end

    test "create_episode/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Podcasts.create_episode(scope, @invalid_attrs)
    end

    test "update_episode/3 with valid data updates the episode" do
      scope = user_scope_fixture()
      episode = episode_fixture(scope)
      update_attrs = %{title: "some updated title", original_audio_url: "some updated original_audio_url", processing_status: "some updated processing_status", transcript_url: "some updated transcript_url", generated_summary: "some updated generated_summary", generated_timestamps: %{}}

      assert {:ok, %Episode{} = episode} = Podcasts.update_episode(scope, episode, update_attrs)
      assert episode.title == "some updated title"
      assert episode.original_audio_url == "some updated original_audio_url"
      assert episode.processing_status == "some updated processing_status"
      assert episode.transcript_url == "some updated transcript_url"
      assert episode.generated_summary == "some updated generated_summary"
      assert episode.generated_timestamps == %{}
    end

    test "update_episode/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      episode = episode_fixture(scope)

      assert_raise MatchError, fn ->
        Podcasts.update_episode(other_scope, episode, %{})
      end
    end

    test "update_episode/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      episode = episode_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Podcasts.update_episode(scope, episode, @invalid_attrs)
      assert episode == Podcasts.get_episode!(scope, episode.id)
    end

    test "delete_episode/2 deletes the episode" do
      scope = user_scope_fixture()
      episode = episode_fixture(scope)
      assert {:ok, %Episode{}} = Podcasts.delete_episode(scope, episode)
      assert_raise Ecto.NoResultsError, fn -> Podcasts.get_episode!(scope, episode.id) end
    end

    test "delete_episode/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      episode = episode_fixture(scope)
      assert_raise MatchError, fn -> Podcasts.delete_episode(other_scope, episode) end
    end

    test "change_episode/2 returns a episode changeset" do
      scope = user_scope_fixture()
      episode = episode_fixture(scope)
      assert %Ecto.Changeset{} = Podcasts.change_episode(scope, episode)
    end
  end

  describe "podcasts" do
    alias PodcastMcp.Podcasts.Podcast

    import PodcastMcp.AccountsFixtures, only: [user_scope_fixture: 0]
    import PodcastMcp.PodcastsFixtures

    @invalid_attrs %{description: nil, title: nil, cover_art_url: nil}

    test "list_podcasts/1 returns all scoped podcasts" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      other_podcast = podcast_fixture(other_scope)
      assert Podcasts.list_podcasts(scope) == [podcast]
      assert Podcasts.list_podcasts(other_scope) == [other_podcast]
    end

    test "get_podcast!/2 returns the podcast with given id" do
      scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      other_scope = user_scope_fixture()
      assert Podcasts.get_podcast!(scope, podcast.id) == podcast
      assert_raise Ecto.NoResultsError, fn -> Podcasts.get_podcast!(other_scope, podcast.id) end
    end

    test "create_podcast/2 with valid data creates a podcast" do
      valid_attrs = %{description: "some description", title: "some title", cover_art_url: "some cover_art_url"}
      scope = user_scope_fixture()

      assert {:ok, %Podcast{} = podcast} = Podcasts.create_podcast(scope, valid_attrs)
      assert podcast.description == "some description"
      assert podcast.title == "some title"
      assert podcast.cover_art_url == "some cover_art_url"
      assert podcast.user_id == scope.user.id
    end

    test "create_podcast/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Podcasts.create_podcast(scope, @invalid_attrs)
    end

    test "update_podcast/3 with valid data updates the podcast" do
      scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      update_attrs = %{description: "some updated description", title: "some updated title", cover_art_url: "some updated cover_art_url"}

      assert {:ok, %Podcast{} = podcast} = Podcasts.update_podcast(scope, podcast, update_attrs)
      assert podcast.description == "some updated description"
      assert podcast.title == "some updated title"
      assert podcast.cover_art_url == "some updated cover_art_url"
    end

    test "update_podcast/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      podcast = podcast_fixture(scope)

      assert_raise MatchError, fn ->
        Podcasts.update_podcast(other_scope, podcast, %{})
      end
    end

    test "update_podcast/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Podcasts.update_podcast(scope, podcast, @invalid_attrs)
      assert podcast == Podcasts.get_podcast!(scope, podcast.id)
    end

    test "delete_podcast/2 deletes the podcast" do
      scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      assert {:ok, %Podcast{}} = Podcasts.delete_podcast(scope, podcast)
      assert_raise Ecto.NoResultsError, fn -> Podcasts.get_podcast!(scope, podcast.id) end
    end

    test "delete_podcast/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      assert_raise MatchError, fn -> Podcasts.delete_podcast(other_scope, podcast) end
    end

    test "change_podcast/2 returns a podcast changeset" do
      scope = user_scope_fixture()
      podcast = podcast_fixture(scope)
      assert %Ecto.Changeset{} = Podcasts.change_podcast(scope, podcast)
    end
  end
end
