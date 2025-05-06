defmodule PodcastMcp.Podcasts.Podcast do
  use Ecto.Schema
  import Ecto.Changeset

  schema "podcasts" do
    field :title, :string
    field :description, :string
    field :cover_art_url, :string
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(podcast, attrs, user_scope) do
    podcast
    |> cast(attrs, [:title, :description, :cover_art_url])
    |> validate_required([:title, :description, :cover_art_url])
    |> put_change(:user_id, user_scope.user.id)
  end
end
