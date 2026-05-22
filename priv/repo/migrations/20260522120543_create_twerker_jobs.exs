defmodule ArchiveClassifier.Repo.Migrations.CreateTwerkerJobs do
  use Ecto.Migration

  def change do
    create table(:twerker_jobs) do
      add :module, :string, null: false
      add :function, :string, null: false
      add :args, :binary, null: false
      add :status, :string, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 3
      add :error, :text
      add :queued_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:twerker_jobs, [:status])
    create index(:twerker_jobs, [:status, :queued_at])
  end
end
