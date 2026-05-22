defmodule ArchiveClassifier.Repo.Migrations.AddDurationOrderIndex do
  use Ecto.Migration

  def change do
    create index(:videos, [:collection, :duration])
  end
end
