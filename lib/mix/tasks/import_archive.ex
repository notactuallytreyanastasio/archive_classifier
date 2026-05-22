defmodule Mix.Tasks.ImportArchive do
  @moduledoc """
  One-time import of video metadata from the archive_tv SQLite database
  into our Postgres database.

  Usage:
    mix import_archive [path_to_archive_tv.db]

  Defaults to ../archive_tv/data/archive-tv.db relative to this project.
  """

  use Mix.Task

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  @shortdoc "Import videos from archive_tv SQLite into Postgres"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    db_path =
      case args do
        [path] -> path
        [] -> Path.expand("../archive_tv/data/archive-tv.db")
      end

    unless File.exists?(db_path) do
      Mix.raise("SQLite database not found at: #{db_path}")
    end

    Mix.shell().info("Importing from: #{db_path}")

    {:ok, conn} = Exqlite.Basic.open(db_path)

    {:ok, result} =
      Exqlite.Basic.exec(conn, """
      SELECT id, title, description, duration, primary_video_url, collection, files_json
      FROM videos
      ORDER BY duration ASC
      """)
      |> then(fn
        {:ok, _query, %{columns: cols, rows: rows}} -> {:ok, {cols, rows}}
        {:ok, _query, %{columns: cols, rows: rows}, _conn} -> {:ok, {cols, rows}}
        other -> other
      end)

    Exqlite.Basic.close(conn)

    {columns, rows} = result

    videos =
      Enum.map(rows, fn row ->
        columns
        |> Enum.zip(row)
        |> Map.new(fn {col, val} -> {String.to_atom(col), val} end)
      end)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(videos, fn attrs ->
        attrs
        |> Map.put(:archive_id, Map.fetch!(attrs, :id))
        |> Map.delete(:id)
        |> Map.put(:classification_status, :pending)
        |> Map.put(:tags, [])
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    # Batch insert in chunks of 100
    {total, _} =
      entries
      |> Enum.chunk_every(100)
      |> Enum.reduce({0, 0}, fn chunk, {total, _} ->
        {count, _} = Repo.insert_all(Video, chunk, on_conflict: :nothing, conflict_target: :archive_id)
        {total + count, 0}
      end)

    Mix.shell().info("Done. Inserted #{total} of #{length(entries)} videos.")
  end
end
