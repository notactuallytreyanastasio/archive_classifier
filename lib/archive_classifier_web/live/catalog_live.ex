defmodule ArchiveClassifierWeb.CatalogLive do
  @moduledoc """
  Browse, search, and trigger classification on archive videos.
  """

  use ArchiveClassifierWeb, :live_view

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Cache

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Archive Catalog")
     |> assign(:search, "")
     |> assign(:stats, Cache.stats())
     |> assign(:grouped_videos, Cache.videos_by_collection())}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:grouped_videos, Cache.search_by_collection(search))}
  end

  @impl true
  def handle_event("classify", %{"id" => id}, socket) do
    video_id = String.to_integer(id)
    video = Archive.get_video!(video_id)

    case Archive.queue_for_classification(video) do
      {:ok, _updated} ->
        Cache.reload(video_id)

        {:noreply,
         socket
         |> assign(:grouped_videos, Cache.search_by_collection(socket.assigns.search))
         |> assign(:stats, Cache.stats())}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to queue video.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold text-gray-900">Archive Catalog</h1>
          <p class="mt-1 text-sm text-gray-500">
            {format_number(@stats.total)} videos &middot;
            {format_number(@stats.pending)} pending &middot;
            {format_number(@stats.queued)} queued &middot;
            {format_number(@stats.classified)} classified
          </p>
        </header>

        <form phx-change="search" class="mb-8">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by title or description..."
            phx-debounce="300"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            id="catalog-search"
          />
        </form>

        <div :if={@grouped_videos == []} class="text-center py-12 text-gray-400">
          No videos found.
        </div>

        <div :for={{collection, videos} <- @grouped_videos} class="mb-10">
          <div class="flex items-baseline gap-3 mb-3 border-b border-gray-200 pb-2">
            <h2 class="text-lg font-semibold text-gray-800">
              {format_collection(collection)}
            </h2>
            <span class="text-xs text-gray-400">{length(videos)} videos</span>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            <div
              :for={video <- videos}
              id={"video-#{video.id}"}
              class="p-3 bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
            >
              <h3 class="text-sm font-medium text-gray-900 truncate" title={String.trim(video.title)}>
                {String.trim(video.title)}
              </h3>
              <p class="text-xs text-gray-500 mt-1">
                {format_duration(video.duration)}
              </p>

              <div :if={video.tags != []} class="mt-1.5">
                <span
                  :for={tag <- video.tags}
                  class="inline-block px-1.5 py-0.5 bg-blue-50 text-blue-700 text-xs rounded mr-1 mb-1"
                >
                  {tag}
                </span>
              </div>

              <div class="flex items-center justify-between mt-2 pt-2 border-t border-gray-100">
                <span class={["text-xs px-2 py-0.5 rounded", status_class(video.classification_status)]}>
                  {video.classification_status}
                </span>

                <button
                  :if={video.classification_status == :pending}
                  phx-click="classify"
                  phx-value-id={video.id}
                  class="text-xs px-3 py-1 bg-gray-900 text-white rounded hover:bg-gray-700 transition-colors"
                >
                  Classify
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_duration(nil), do: "unknown"

  defp format_duration(seconds) when is_float(seconds) do
    total = trunc(seconds)
    hours = div(total, 3600)
    minutes = div(rem(total, 3600), 60)
    secs = rem(total, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  defp format_number(n), do: Integer.to_string(n)

  defp format_collection("markpines"), do: "Mark Pines Collection"
  defp format_collection("mp_ronwood"), do: "Ron Wood"
  defp format_collection("markpines_fashion"), do: "Fashion"
  defp format_collection("markpines_jacksonbrowne"), do: "Jackson Browne"
  defp format_collection("markpines_musicindustry"), do: "Music Industry"
  defp format_collection("markpines_rascals"), do: "The Rascals"
  defp format_collection("diamondheadtapes"), do: "Diamond Head Tapes"
  defp format_collection(other), do: other

  defp status_class(:pending), do: "bg-gray-100 text-gray-600"
  defp status_class(:queued), do: "bg-amber-100 text-amber-700"
  defp status_class(:classifying), do: "bg-blue-100 text-blue-700"
  defp status_class(:classified), do: "bg-green-100 text-green-700"
  defp status_class(:failed), do: "bg-red-100 text-red-700"
  defp status_class(_), do: "bg-gray-100 text-gray-600"
end
