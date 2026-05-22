defmodule ArchiveClassifierWeb.CatalogLive do
  @moduledoc """
  Browse, search, and trigger classification on archive videos.
  Collection-first view with drill-in to individual videos.
  """

  use ArchiveClassifierWeb, :live_view

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Cache

  @sort_options [
    {"duration_asc", "Duration (shortest first)"},
    {"duration_desc", "Duration (longest first)"},
    {"title_asc", "Title (A-Z)"},
    {"title_desc", "Title (Z-A)"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Archive Catalog")
     |> assign(:search, "")
     |> assign(:sort, "duration_asc")
     |> assign(:sort_options, @sort_options)
     |> assign(:selected_collection, nil)
     |> assign(:stats, Cache.stats())
     |> assign_collections()
     |> assign_videos()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign_collections()
     |> assign_videos()}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:sort, sort)
     |> assign_videos()}
  end

  @impl true
  def handle_event("select_collection", %{"collection" => collection}, socket) do
    {:noreply,
     socket
     |> assign(:selected_collection, collection)
     |> assign_videos()}
  end

  @impl true
  def handle_event("back_to_collections", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_collection, nil)
     |> assign_videos()}
  end

  @impl true
  def handle_event("classify", %{"id" => id}, socket) do
    video_id = String.to_integer(id)
    video = Archive.get_video!(video_id)

    # Enqueue in the supervised pipeline
    ArchiveClassifier.Pipeline.TranscriptionProducer.enqueue(video_id)

    case Archive.queue_for_classification(video) do
      {:ok, _updated} ->
        Cache.reload(video_id)

        {:noreply,
         socket
         |> assign(:stats, Cache.stats())
         |> assign_videos()
         |> put_flash(:info, "Transcription started for #{String.trim(video.title)}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to queue video.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-8">
        <header class="mb-6">
          <h1 class="text-2xl font-semibold text-gray-900">Archive Catalog</h1>
          <p class="mt-1 text-sm text-gray-500">
            {format_number(@stats.total)} videos &middot;
            {format_number(@stats.pending)} pending &middot;
            {format_number(@stats.queued)} queued &middot;
            {format_number(@stats.classified)} classified
          </p>
        </header>

        <div class="flex gap-3 mb-6">
          <form phx-change="search" class="flex-1">
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

          <form phx-change="sort">
            <select
              name="sort"
              class="px-3 py-2 border border-gray-300 rounded-lg text-sm bg-white focus:ring-2 focus:ring-blue-500"
              id="catalog-sort"
            >
              <option :for={{val, label} <- @sort_options} value={val} selected={val == @sort}>
                {label}
              </option>
            </select>
          </form>
        </div>

        <%!-- Collection overview --%>
        <div :if={@selected_collection == nil}>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <button
              :for={col <- @collections}
              phx-click="select_collection"
              phx-value-collection={col.name}
              class="text-left p-4 bg-white border border-gray-200 rounded-lg hover:border-gray-400 hover:shadow-sm transition-all cursor-pointer"
            >
              <div class="flex items-start gap-3">
                <img
                  src={thumbnail_url(col.sample_id)}
                  class="w-16 h-12 object-cover rounded bg-gray-100"
                  loading="lazy"
                />
                <div class="flex-1 min-w-0">
                  <h2 class="text-sm font-semibold text-gray-900">
                    {format_collection(col.name)}
                  </h2>
                  <p class="text-xs text-gray-500 mt-0.5">
                    {col.count} videos &middot; {format_total_duration(col.total_duration)}
                  </p>
                </div>
              </div>
            </button>
          </div>
        </div>

        <%!-- Drilled-in collection view --%>
        <div :if={@selected_collection != nil}>
          <div class="flex items-center gap-3 mb-4">
            <button
              phx-click="back_to_collections"
              class="text-sm text-blue-600 hover:text-blue-800 flex items-center gap-1"
            >
              &larr; All collections
            </button>
            <h2 class="text-lg font-semibold text-gray-800">
              {format_collection(@selected_collection)}
            </h2>
            <span class="text-xs text-gray-400">{length(@videos)} videos</span>
          </div>

          <div :if={@videos == []} class="text-center py-12 text-gray-400">
            No videos found.
          </div>

          <div class="grid gap-3" style="grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));">
            <div
              :for={video <- @videos}
              id={"video-#{video.id}"}
              class="bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors overflow-visible group relative"
            >
              <img
                src={thumbnail_url(video.id)}
                class="w-full h-32 object-cover bg-gray-100"
                loading="lazy"
              />
              <div class="p-3">
                <h3 class="text-sm font-medium text-gray-900 cursor-default">
                  {String.trim(video.title)}
                </h3>
                <div
                  :if={video.description && String.trim(video.description) != String.trim(video.title)}
                  class="absolute z-10 left-2 right-2 bottom-full mb-1 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg leading-relaxed opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-opacity pointer-events-none"
                >
                  {strip_html(video.description)}
                </div>
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
                  <span class={[
                    "text-xs px-2 py-0.5 rounded",
                    status_class(video.classification_status)
                  ]}>
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

                  <.link
                    :if={video.classification_status == :classified}
                    navigate={~p"/videos/#{video.id}/transcript"}
                    class="text-xs px-3 py-1 bg-blue-600 text-white rounded hover:bg-blue-500 transition-colors"
                  >
                    View Transcript
                  </.link>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Assign helpers

  defp assign_collections(socket) do
    videos = filtered_videos(socket.assigns.search)

    collections =
      videos
      |> Enum.group_by(& &1.collection)
      |> Enum.map(fn {name, vids} ->
        %{
          name: name,
          count: length(vids),
          total_duration: vids |> Enum.map(& &1.duration) |> Enum.reject(&is_nil/1) |> Enum.sum(),
          sample_id: List.first(vids).id
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    assign(socket, :collections, collections)
  end

  defp assign_videos(%{assigns: %{selected_collection: nil}} = socket) do
    assign(socket, :videos, [])
  end

  defp assign_videos(%{assigns: %{selected_collection: col, search: search, sort: sort}} = socket) do
    videos =
      filtered_videos(search)
      |> Enum.filter(&(&1.collection == col))
      |> sort_videos(sort)

    assign(socket, :videos, videos)
  end

  defp filtered_videos(search), do: Cache.search(search)

  defp sort_videos(videos, "duration_asc"), do: Enum.sort_by(videos, & &1.duration)
  defp sort_videos(videos, "duration_desc"), do: Enum.sort_by(videos, & &1.duration, :desc)
  defp sort_videos(videos, "title_asc"), do: Enum.sort_by(videos, & &1.title)
  defp sort_videos(videos, "title_desc"), do: Enum.sort_by(videos, & &1.title, :desc)
  defp sort_videos(videos, _), do: videos

  # Formatters

  defp thumbnail_url(video_id), do: "/thumbnails/#{video_id}"

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

  defp format_total_duration(seconds) do
    hours = trunc(seconds / 3600)

    cond do
      hours > 0 -> "#{hours}h total"
      true -> "#{trunc(seconds / 60)}m total"
    end
  end

  defp format_number(n), do: Integer.to_string(n)

  defp strip_html(text) do
    text
    |> String.replace(~r/<br\s*\/?>/, " ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

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
