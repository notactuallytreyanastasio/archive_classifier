defmodule ArchiveClassifier.Repo.Migrations.CreateVideoFrames do
  use Ecto.Migration

  def change do
    create table(:video_frames) do
      add :video_id, references(:videos, on_delete: :delete_all), null: false
      add :timestamp, :float, null: false
      add :image, :binary, null: false

      timestamps()
    end

    create index(:video_frames, [:video_id, :timestamp])
  end
end
