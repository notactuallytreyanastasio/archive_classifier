defmodule ArchiveClassifier.Repo.Migrations.AddTranscriptFts do
  use Ecto.Migration

  def change do
    # tsvector column on transcripts for full-text search
    alter table(:transcripts) do
      add :search_vector, :tsvector
    end

    # GIN index for fast FTS queries
    create index(:transcripts, [:search_vector], using: :gin)

    # Auto-populate search_vector from text column
    execute(
      "UPDATE transcripts SET search_vector = to_tsvector('english', text)",
      ""
    )

    # Trigger to keep search_vector in sync on insert/update
    execute(
      """
      CREATE OR REPLACE FUNCTION transcripts_search_vector_trigger() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := to_tsvector('english', COALESCE(NEW.text, ''));
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS transcripts_search_vector_trigger();"
    )

    execute(
      """
      CREATE TRIGGER transcripts_search_vector_update
      BEFORE INSERT OR UPDATE OF text ON transcripts
      FOR EACH ROW EXECUTE FUNCTION transcripts_search_vector_trigger();
      """,
      "DROP TRIGGER IF EXISTS transcripts_search_vector_update ON transcripts;"
    )

    # Also add tsvector on videos for title+description FTS
    alter table(:videos) do
      add :search_vector, :tsvector
    end

    create index(:videos, [:search_vector], using: :gin)

    execute(
      "UPDATE videos SET search_vector = to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(description, ''))",
      ""
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION videos_search_vector_trigger() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.description, ''));
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS videos_search_vector_trigger();"
    )

    execute(
      """
      CREATE TRIGGER videos_search_vector_update
      BEFORE INSERT OR UPDATE OF title, description ON videos
      FOR EACH ROW EXECUTE FUNCTION videos_search_vector_trigger();
      """,
      "DROP TRIGGER IF EXISTS videos_search_vector_update ON videos;"
    )
  end
end
