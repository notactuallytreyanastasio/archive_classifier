defmodule ArchiveClassifier.Archive do
  @moduledoc """
  Context for querying the video catalog.
  """

  import Ecto.Query

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  @type list_opts :: [search: String.t(), status: String.t(), limit: pos_integer(), offset: non_neg_integer()]

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
  @spec get_video!(String.t()) :: Video.t()
  def get_video!(id), do: Repo.get!(Video, id)

  @doc """
  Marks a video as queued for classification.
  """
  @spec queue_for_classification(Video.t()) :: {:ok, Video.t()} | {:error, Ecto.Changeset.t()}
  def queue_for_classification(%Video{} = video) do
    video
    |> Video.changeset(%{classification_status: "queued"})
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
