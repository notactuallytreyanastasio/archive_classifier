defmodule Mix.Tasks.FetchThumbnails do
  @moduledoc """
  Fetches thumbnail images from archive.org for all videos that don't have one yet.
  Stores them as binary blobs in Postgres.

  Usage:
    mix fetch_thumbnails
  """

  use Mix.Task

  import Ecto.Query

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  @shortdoc "Fetch thumbnail images from archive.org into Postgres"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    videos =
      Video
      |> where([v], is_nil(v.thumbnail))
      |> select([v], {v.id, v.archive_id})
      |> Repo.all()

    total = length(videos)
    Mix.shell().info("Fetching thumbnails for #{total} videos...")

    {ok, failed} =
      videos
      |> Task.async_stream(
        fn {id, archive_id} -> fetch_one(id, archive_id) end,
        max_concurrency: 10,
        timeout: :infinity
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, :ok}, {ok, failed} -> {ok + 1, failed}
        {:ok, :error}, {ok, failed} -> {ok, failed + 1}
        {:exit, _reason}, {ok, failed} -> {ok, failed + 1}
      end)

    Mix.shell().info("Done. Fetched: #{ok}, Failed: #{failed}")
  end

  defp fetch_one(id, archive_id) do
    url = "https://archive.org/services/img/#{archive_id}"

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        Repo.update_all(
          from(v in Video, where: v.id == ^id),
          set: [thumbnail: body, updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
        )

        :ok

      _ ->
        :error
    end
  rescue
    _ -> :error
  end
end
