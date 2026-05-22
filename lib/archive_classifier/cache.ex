defmodule ArchiveClassifier.Cache do
  @moduledoc """
  ETS cache that holds all videos in memory.

  The entire catalog (1,371 videos) fits easily in RAM.
  Load on startup, invalidate and reload when classifications change.
  """

  use GenServer

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  import Ecto.Query

  @table __MODULE__

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns all videos from cache, ordered by duration ascending.
  """
  @spec all_videos() :: [Video.t()]
  def all_videos do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, video} -> video end)
    |> Enum.sort_by(& &1.duration)
  end

  @doc """
  Returns all videos grouped by collection, sorted by collection size descending.
  """
  @spec videos_by_collection() :: [{String.t(), [Video.t()]}]
  def videos_by_collection do
    all_videos()
    |> Enum.group_by(& &1.collection)
    |> Enum.sort_by(fn {_col, vids} -> -length(vids) end)
  end

  @doc """
  Search videos by title or description (case-insensitive).
  """
  @spec search(String.t()) :: [Video.t()]
  def search(""), do: all_videos()
  def search(nil), do: all_videos()

  def search(term) do
    downcased = String.downcase(term)

    all_videos()
    |> Enum.filter(fn video ->
      String.contains?(String.downcase(video.title || ""), downcased) or
        String.contains?(String.downcase(video.description || ""), downcased)
    end)
  end

  @doc """
  Search videos grouped by collection.
  """
  @spec search_by_collection(String.t() | nil) :: [{String.t(), [Video.t()]}]
  def search_by_collection(term) do
    search(term)
    |> Enum.group_by(& &1.collection)
    |> Enum.sort_by(fn {_col, vids} -> -length(vids) end)
  end

  @doc """
  Get a single video by integer id from cache.
  """
  @spec get(integer()) :: Video.t() | nil
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, video}] -> video
      [] -> nil
    end
  end

  @doc """
  Reload a single video from DB into cache (after status change).
  """
  @spec reload(integer()) :: :ok
  def reload(id) do
    video = Repo.get!(Video, id)
    :ets.insert(@table, {video.id, video})
    :ok
  end

  @doc """
  Full reload from database.
  """
  @spec reload_all() :: :ok
  def reload_all do
    GenServer.call(__MODULE__, :reload_all)
  end

  @doc """
  Stats computed from cache.
  """
  @spec stats() :: %{total: non_neg_integer(), pending: non_neg_integer(), queued: non_neg_integer(), classified: non_neg_integer()}
  def stats do
    videos = all_videos()

    %{
      total: length(videos),
      pending: Enum.count(videos, &(&1.classification_status == :pending)),
      queued: Enum.count(videos, &(&1.classification_status == :queued)),
      classified: Enum.count(videos, &(&1.classification_status == :classified))
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    load_all(table)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reload_all, _from, %{table: table} = state) do
    :ets.delete_all_objects(table)
    load_all(table)
    {:reply, :ok, state}
  end

  defp load_all(table) do
    Video
    |> order_by([v], asc: v.duration)
    |> Repo.all()
    |> Enum.each(fn video ->
      :ets.insert(table, {video.id, video})
    end)
  end
end
