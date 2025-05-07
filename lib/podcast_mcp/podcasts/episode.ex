defmodule PodcastMcp.Podcasts.Episode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "episodes" do
    field :title, :string
    field :original_audio_url, :string
    field :processing_status, :string
    field :transcript_url, :string       # For later use
    field :generated_summary, :string    # For later use
    field :generated_timestamps, :map    # For later use

    field :audio, :any, virtual: true   # For the upload form

    # Associations
    belongs_to :podcast, PodcastMcp.Podcasts.Podcast
    belongs_to :user, PodcastMcp.Accounts.User # Make sure PodcastMcp.Accounts.User is correct

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(episode, attrs) do
    episode
    |> cast(attrs, [
      :title,
      :podcast_id,
      :user_id, # <<< --- ADD :user_id HERE ---
      :audio,   # Virtual field for form
      # Fields usually set programmatically after creation/processing:
      :original_audio_url,
      :processing_status,
      :transcript_url,
      :generated_summary,
      :generated_timestamps
    ])
    |> validate_required([
      :title,
      :podcast_id,
      :user_id
      # Add :original_audio_url here if it's always required at creation
      # Add :processing_status here if it has a required initial value
    ])
    |> assoc_constraint(:podcast) # Validates podcast_id exists
    |> assoc_constraint(:user)    # Validates user_id exists
    # Add any other specific validations (e.g., title length)
    # Example: |> validate_length(:title, min: 3)
  end
end
