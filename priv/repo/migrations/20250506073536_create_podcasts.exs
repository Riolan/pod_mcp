defmodule PodcastMcp.Repo.Migrations.CreatePodcasts do
  use Ecto.Migration

  def change do
    create table(:podcasts) do
      add :title, :string
      add :description, :text
      add :cover_art_url, :string
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:podcasts, [:user_id])

  end
end
