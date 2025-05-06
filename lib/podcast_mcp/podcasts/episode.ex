defmodule PodcastMcp.Podcasts.Episode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "episodes" do
    field :title, :string
    field :original_audio_url, :string
    field :processing_status, :string
    field :transcript_url, :string
    field :generated_summary, :string
    field :generated_timestamps, :map
    field :podcast_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(episode, attrs, user_scope) do
    episode
    |> cast(attrs, [:title, :original_audio_url, :processing_status, :transcript_url, :generated_summary, :generated_timestamps])
    |> validate_required([:title, :original_audio_url, :processing_status, :transcript_url, :generated_summary])
    |> put_change(:user_id, user_scope.user.id)
  end
end
