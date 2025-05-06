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
    #field :podcast_id, :id
   # field :user_id, :id

    field :audio, :any, virtual: true

     # Use belongs_to for associations
     belongs_to :podcast, PodcastMcp.Podcasts.Podcast
     belongs_to :user, PodcastMcp.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(episode, attrs) do # Standard changeset/2 signature
    episode
    |> cast(attrs, [
      # Fields allowed from forms/external input:
      :title,
      :podcast_id,
      :user_id,
      :audio,
      # Internal fields - usually set programmatically, not directly cast from user input:
      :original_audio_url,
      :processing_status,
      :transcript_url,
      :generated_summary,
      :generated_timestamps
    ])
    |> validate_required([
        # Fields required to initially create an episode record:
        :title,
        :podcast_id,
        :user_id
      ])
    # Ensures :podcast_id maps to a real Podcast
    |> assoc_constraint(:podcast)
    # Ensures :user_id maps to a real User
    |> assoc_constraint(:user)
    # Add other specific validations if needed (e.g., title length)
    # Example: |> validate_length(:title, min: 3)
  end
end
