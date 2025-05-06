defmodule PodcastMcp.Repo.Migrations.CreateEpisodes do
  use Ecto.Migration

  def change do
    create table(:episodes) do
      add :title, :string
      add :original_audio_url, :string
      add :processing_status, :string
      add :transcript_url, :string
      add :generated_summary, :text
      add :generated_timestamps, :map
      add :podcast_id, references(:podcasts, on_delete: :nothing)
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:episodes, [:user_id])

    create index(:episodes, [:podcast_id])
  end
end
