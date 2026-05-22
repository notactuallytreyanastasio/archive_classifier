defmodule ArchiveClassifier.Repo.Migrations.AddThumbnailToVideos do
  use Ecto.Migration

  def change do
    alter table(:videos) do
      add :thumbnail, :binary
    end
  end
end
