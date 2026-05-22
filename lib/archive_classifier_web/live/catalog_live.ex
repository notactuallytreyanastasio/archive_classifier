defmodule ArchiveClassifierWeb.CatalogLive do
  @moduledoc """
  Browse, search, and trigger classification on archive videos.
  """

  use ArchiveClassifierWeb, :live_view

  alias ArchiveClassifier.Archive

  @impl true
  def mount(_params, _session, socket) do
    stats = Archive.stats()
    videos = Archive.list_videos(limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Archive Catalog")
     |> assign(:search, "")
     |> assign(:stats, stats)
     |> stream(:videos, videos)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    videos = Archive.list_videos(search: search, limit: 50)

    {:noreply,
     socket
     |> assign(:search, search)
     |> stream(:videos, videos, reset: true)}
  end

  @impl true
  def handle_event("classify", %{"id" => id}, socket) do
    video = Archive.get_video!(id)

    case Archive.queue_for_classification(video) do
      {:ok, updated} ->
        {:noreply, stream_insert(socket, :videos, updated)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to queue video.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-5xl mx-auto px-4 py-8">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold text-gray-900">Archive Catalog</h1>
          <p class="mt-1 text-sm text-gray-500">
            {format_number(@stats.total)} videos &middot;
            {format_number(@stats.pending)} pending &middot;
            {format_number(@stats.queued)} queued &middot;
            {format_number(@stats.classified)} classified
          </p>
        </header>

        <form phx-change="search" class="mb-6">
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

        <div id="videos" phx-update="stream" class="space-y-2">
          <div class="hidden only:block text-center py-12 text-gray-400">
            No videos found.
          </div>
          <div
            :for={{dom_id, video} <- @streams.videos}
            id={dom_id}
            class="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            <div class="flex-1 min-w-0 mr-4">
              <h3 class="text-sm font-medium text-gray-900 truncate">
                {String.trim(video.title)}
              </h3>
              <p class="text-xs text-gray-500 mt-0.5">
                {format_duration(video.duration)} &middot; {video.collection}
                <span :if={video.tags != []} class="ml-2">
                  <span
                    :for={tag <- video.tags}
                    class="inline-block px-1.5 py-0.5 bg-blue-50 text-blue-700 text-xs rounded mr-1"
                  >
                    {tag}
                  </span>
                </span>
              </p>
            </div>

            <div class="flex items-center gap-2">
              <span class={[
                "text-xs px-2 py-0.5 rounded",
                status_class(video.classification_status)
              ]}>
                {video.classification_status}
              </span>

              <button
                :if={video.classification_status == "pending"}
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

  defp status_class("pending"), do: "bg-gray-100 text-gray-600"
  defp status_class("queued"), do: "bg-amber-100 text-amber-700"
  defp status_class("classifying"), do: "bg-blue-100 text-blue-700"
  defp status_class("classified"), do: "bg-green-100 text-green-700"
  defp status_class(_), do: "bg-gray-100 text-gray-600"
end
