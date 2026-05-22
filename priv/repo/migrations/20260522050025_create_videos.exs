defmodule ArchiveClassifier.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos) do
      add :archive_id, :text, null: false
      add :title, :text, null: false
      add :description, :text
      add :duration, :float
      add :primary_video_url, :text, null: false
      add :collection, :text, null: false
      add :files_json, :text, null: false
      add :classification_status, :string, default: "pending", null: false
      add :tags, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:videos, [:archive_id])
    create index(:videos, [:classification_status])
    create index(:videos, [:duration])
  end
end
