defmodule ArchiveClassifier.Repo.Migrations.CreateTranscripts do
  use Ecto.Migration

  def change do
    create table(:transcripts) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :start_time, :float, null: false
      add :end_time, :float, null: false
      add :text, :text, null: false

      timestamps()
    end

    create index(:transcripts, [:video_id])
    create index(:transcripts, [:start_time])
  end
end
