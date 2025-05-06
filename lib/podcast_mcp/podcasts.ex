defmodule PodcastMcp.Podcasts do
  @moduledoc """
  The Podcasts context.
  """

  import Ecto.Query, warn: false
  alias PodcastMcp.Repo
  alias PodcastMcp.Podcasts.Episode
  alias PodcastMcp.Podcasts.Podcast
  alias PodcastMcp.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any podcast changes.

  The broadcasted messages match the pattern:

    * {:created, %Podcast{}}
    * {:updated, %Podcast{}}
    * {:deleted, %Podcast{}}

  """
  def subscribe_podcasts(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(PodcastMcp.PubSub, "user:#{key}:podcasts")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(PodcastMcp.PubSub, "user:#{key}:podcasts", message)
  end

  @doc """
  Returns the list of podcasts.

  ## Examples

      iex> list_podcasts(scope)
      [%Podcast{}, ...]

  """
  def list_podcasts(%Scope{} = scope) do
    Repo.all(from podcast in Podcast, where: podcast.user_id == ^scope.user.id)
  end

  @doc """
  Gets a single podcast.

  Raises `Ecto.NoResultsError` if the Podcast does not exist.

  ## Examples

      iex> get_podcast!(123)
      %Podcast{}

      iex> get_podcast!(456)
      ** (Ecto.NoResultsError)

  """
  def get_podcast!(%Scope{} = scope, id) do
    Repo.get_by!(Podcast, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a podcast.

  ## Examples

      iex> create_podcast(%{field: value})
      {:ok, %Podcast{}}

      iex> create_podcast(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_podcast(%Scope{} = scope, attrs) do
    with {:ok, podcast = %Podcast{}} <-
           %Podcast{}
           |> Podcast.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast(scope, {:created, podcast})
      {:ok, podcast}
    end
  end

  @doc """
  Updates a podcast.

  ## Examples

      iex> update_podcast(podcast, %{field: new_value})
      {:ok, %Podcast{}}

      iex> update_podcast(podcast, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_podcast(%Scope{} = scope, %Podcast{} = podcast, attrs) do
    true = podcast.user_id == scope.user.id

    with {:ok, podcast = %Podcast{}} <-
           podcast
           |> Podcast.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, podcast})
      {:ok, podcast}
    end
  end

  @doc """
  Deletes a podcast.

  ## Examples

      iex> delete_podcast(podcast)
      {:ok, %Podcast{}}

      iex> delete_podcast(podcast)
      {:error, %Ecto.Changeset{}}

  """
  def delete_podcast(%Scope{} = scope, %Podcast{} = podcast) do
    true = podcast.user_id == scope.user.id

    with {:ok, podcast = %Podcast{}} <-
           Repo.delete(podcast) do
      broadcast(scope, {:deleted, podcast})
      {:ok, podcast}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking podcast changes.

  ## Examples

      iex> change_podcast(podcast)
      %Ecto.Changeset{data: %Podcast{}}

  """
  def change_podcast(%Scope{} = scope, %Podcast{} = podcast, attrs \\ %{}) do
    true = podcast.user_id == scope.user.id

    Podcast.changeset(podcast, attrs, scope)
  end



   @doc """
  Returns an `%Ecto.Changeset{}` for tracking episode changes.

  Typically used to build forms.

  ## Examples

      iex> change_episode(%Episode{})
      %Ecto.Changeset{data: %Episode{}}

  """
  def change_episode(%Episode{} = episode, attrs \\ %{}) do
    Episode.changeset(episode, attrs)
  end



end
