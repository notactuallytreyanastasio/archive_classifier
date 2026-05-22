defmodule ArchiveClassifier.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos, primary_key: false) do
      add :id, :text, primary_key: true
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

    create index(:videos, [:classification_status])
    create index(:videos, [:duration])
  end
end
