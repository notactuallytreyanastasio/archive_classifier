defmodule ArchiveClassifier.Archive do
  @moduledoc """
  Context for querying the video catalog.
  """

  import Ecto.Query

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  @type list_opts :: [search: String.t(), status: Video.status(), limit: pos_integer(), offset: non_neg_integer()]

  @doc """
  Lists videos with optional filtering by search term and classification status.
  Results ordered by duration ascending (short videos first).
  """
  @spec list_videos(list_opts()) :: [Video.t()]
  def list_videos(opts \\ []) do
    Video
    |> apply_search(opts[:search])
    |> apply_status(opts[:status])
    |> order_by([v], asc: v.duration)
    |> limit(^(opts[:limit] || 50))
    |> offset(^(opts[:offset] || 0))
    |> Repo.all()
  end

  @doc """
  Returns the total count of videos matching the given filters.
  """
  @spec count_videos(list_opts()) :: non_neg_integer()
  def count_videos(opts \\ []) do
    Video
    |> apply_search(opts[:search])
    |> apply_status(opts[:status])
    |> Repo.aggregate(:count)
  end

  @doc """
  Fetches a single video by ID.
  """
  @spec get_video!(integer()) :: Video.t()
  def get_video!(id), do: Repo.get!(Video, id)

  @doc """
  Marks a video as queued for classification.
  """
  @spec queue_for_classification(Video.t()) :: {:ok, Video.t()} | {:error, Ecto.Changeset.t()}
  def queue_for_classification(%Video{} = video) do
    video
    |> Video.changeset(%{classification_status: :queued})
    |> Repo.update()
  end

  @doc """
  Returns summary stats for the dashboard.
  """
  @spec stats() :: %{total: non_neg_integer(), pending: non_neg_integer(), queued: non_neg_integer(), classified: non_neg_integer()}
  def stats do
    query =
      from v in Video,
        select: %{
          total: count(v.id),
          pending: count(fragment("CASE WHEN ? = 'pending' THEN 1 END", v.classification_status)),
          queued: count(fragment("CASE WHEN ? = 'queued' THEN 1 END", v.classification_status)),
          classified: count(fragment("CASE WHEN ? = 'classified' THEN 1 END", v.classification_status))
        }

    Repo.one(query)
  end

  @doc """
  Lists videos grouped by collection.
  Returns a list of `{collection_name, [Video.t()]}` tuples, sorted by collection name.
  """
  @spec list_videos_by_collection(list_opts()) :: [{String.t(), [Video.t()]}]
  def list_videos_by_collection(opts \\ []) do
    Video
    |> apply_search(opts[:search])
    |> apply_status(opts[:status])
    |> order_by([v], [asc: v.collection, asc: v.duration])
    |> Repo.all()
    |> Enum.group_by(& &1.collection)
    |> Enum.sort_by(fn {_col, vids} -> -length(vids) end)
  end

  @doc """
  Returns collection names with their video counts.
  """
  @spec collection_counts() :: [{String.t(), non_neg_integer()}]
  def collection_counts do
    from(v in Video,
      group_by: v.collection,
      select: {v.collection, count(v.id)},
      order_by: [desc: count(v.id)]
    )
    |> Repo.all()
  end

  @doc """
  Lists videos with composable filters including duration range.
  For the admin dashboard.
  """
  @spec list_videos_filtered(keyword()) :: [Video.t()]
  def list_videos_filtered(opts \\ []) do
    Video
    |> apply_search(opts[:search])
    |> apply_status(opts[:status])
    |> apply_collection(opts[:collection])
    |> apply_duration_range(opts[:min_duration], opts[:max_duration])
    |> order_by([v], asc: v.duration)
    |> Repo.all()
  end

  @doc """
  Mass-enqueue videos for transcription via Twerker.
  """
  @spec enqueue_videos([integer()]) :: non_neg_integer()
  def enqueue_videos(video_ids) when is_list(video_ids) do
    Enum.each(video_ids, fn id ->
      Twerker.enqueue(ArchiveClassifier.Pipeline.Transcribe, :run, [id])
    end)

    {count, _} =
      from(v in Video, where: v.id in ^video_ids and v.classification_status == :pending)
      |> Repo.update_all(set: [classification_status: :queued])

    count
  end

  @doc """
  Full-text search across video titles, descriptions, AND transcript content.
  Returns videos that match in either their metadata or their transcripts.
  """
  @spec search_videos_fts(String.t()) :: [Video.t()]
  def search_videos_fts(""), do: []
  def search_videos_fts(nil), do: []

  def search_videos_fts(query) do
    tsquery = to_tsquery(query)
    ilike_term = "%#{query}%"

    # Videos matching in title/description (FTS + ILIKE fallback)
    video_ids_from_metadata =
      from(v in Video,
        where:
          fragment("? @@ to_tsquery('english', ?)", v.search_vector, ^tsquery) or
            ilike(v.title, ^ilike_term) or
            ilike(v.description, ^ilike_term),
        select: v.id
      )
      |> Repo.all()

    # Videos matching in transcript content (FTS + ILIKE fallback)
    video_ids_from_transcripts =
      from(t in ArchiveClassifier.Classification.Transcript,
        where:
          fragment("? @@ to_tsquery('english', ?)", t.search_vector, ^tsquery) or
            ilike(t.text, ^ilike_term),
        select: t.video_id,
        distinct: true
      )
      |> Repo.all()

    all_ids = Enum.uniq(video_ids_from_metadata ++ video_ids_from_transcripts)

    case all_ids do
      [] -> []
      ids -> from(v in Video, where: v.id in ^ids, order_by: [asc: v.duration]) |> Repo.all()
    end
  end

  # Convert user search to tsquery format: "ron wood guitar" → "ron & wood & guitar"
  defp to_tsquery(query) do
    query
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" & ")
  end

  defp apply_collection(query, nil), do: query
  defp apply_collection(query, ""), do: query
  defp apply_collection(query, "all"), do: query
  defp apply_collection(query, collection), do: from(v in query, where: v.collection == ^collection)

  defp apply_duration_range(query, nil, nil), do: query
  defp apply_duration_range(query, min, nil) when is_number(min), do: from(v in query, where: v.duration >= ^min)
  defp apply_duration_range(query, nil, max) when is_number(max), do: from(v in query, where: v.duration <= ^max)
  defp apply_duration_range(query, min, max) when is_number(min) and is_number(max), do: from(v in query, where: v.duration >= ^min and v.duration <= ^max)
  defp apply_duration_range(query, _, _), do: query

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    term = "%#{search}%"

    from v in query,
      where: ilike(v.title, ^term) or ilike(v.description, ^term)
  end

  defp apply_status(query, nil), do: query
  defp apply_status(query, ""), do: query
  defp apply_status(query, status), do: from(v in query, where: v.classification_status == ^status)
end
