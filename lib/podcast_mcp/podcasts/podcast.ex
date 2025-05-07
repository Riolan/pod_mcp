defmodule PodcastMcp.Podcasts.Podcast do
  use Ecto.Schema
  import Ecto.Changeset

  schema "podcasts" do
    field :title, :string
    field :description, :string
    field :cover_art_url, :string

    belongs_to :user, PodcastMcp.Accounts.User # Make sure User schema is aliased or fully qualified

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a podcast using attributes directly.
  This version expects `user_id` to be in `attrs`.
  """
  def changeset(podcast, attrs) do
    podcast
    |> cast(attrs, [:title, :description, :cover_art_url, :user_id])
    |> validate_required([:title, :description, :user_id])
    # Add other validations as needed (e.g., title length)
    |> assoc_constraint(:user) # Validates that the user_id refers to an existing user
  end

  @doc """
  Builds a changeset for a podcast using a user_scope.
  Kept for compatibility if used elsewhere (e.g., by generated LiveView code).
  """
  # If you have a Scope struct, ensure it's aliased or fully qualified.
  # If user_scope is just a map containing the user, adjust the pattern.
  def changeset(podcast, attrs, user_scope) do # Assuming user_scope has a .user field
    podcast
    |> cast(attrs, [:title, :description, :cover_art_url])
    |> validate_required([:title, :description])
    |> put_change(:user_id, user_scope.user.id) # Sets user_id from scope
    |> assoc_constraint(:user)
  end
end
