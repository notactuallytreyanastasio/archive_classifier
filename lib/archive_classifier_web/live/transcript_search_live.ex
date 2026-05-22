defmodule ArchiveClassifierWeb.TranscriptSearchLive do
  @moduledoc """
  Per-video transcript viewer with text search.

  Shows all transcript segments for a classified video, with a search
  input that filters to matching segments. State is fully URL-encoded:
  `/videos/:id/transcript?q=guitar`
  """

  use ArchiveClassifierWeb, :live_view

  import Ecto.Query

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Classification.Transcript
  alias ArchiveClassifier.Classification.VideoFrame
  alias ArchiveClassifier.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    video = Archive.get_video!(String.to_integer(id))

    all_segments =
      Transcript
      |> where([t], t.video_id == ^video.id)
      |> order_by([t], asc: t.start_time)
      |> Repo.all()

    frames =
      VideoFrame
      |> where([f], f.video_id == ^video.id)
      |> order_by([f], asc: f.timestamp)
      |> select([f], %{id: f.id, timestamp: f.timestamp})
      |> Repo.all()

    {:ok,
     socket
     |> assign(:video, video)
     |> assign(:all_segments, all_segments)
     |> assign(:frames, frames)
     |> assign(:page_title, String.trim(video.title))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")
    segments = filter_segments(socket.assigns.all_segments, query)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:segments, segments)}
  end

  @impl true
  def handle_event("filter", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/videos/#{socket.assigns.video.id}/transcript?#{%{q: query}}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="mb-6">
          <a href="/" class="text-sm text-blue-600 hover:text-blue-800">&larr; Back to catalog</a>
        </div>

        <header class="mb-6 flex items-start gap-4">
          <img
            src={"/thumbnails/#{@video.id}"}
            class="w-24 h-16 object-cover rounded bg-gray-100 shrink-0"
          />
          <div>
            <h1 class="text-xl font-semibold text-gray-900">{String.trim(@video.title)}</h1>
            <p class="text-sm text-gray-500 mt-0.5">
              {format_duration(@video.duration)} &middot; {@video.collection} &middot;
              {length(@all_segments)} segments transcribed
            </p>
          </div>
        </header>

        <%!-- Filmstrip timeline --%>
        <div :if={@frames != []} class="mb-6">
          <div
            id="filmstrip"
            class="flex gap-0.5 overflow-x-auto pb-2 rounded-lg bg-gray-900 p-2"
            phx-hook=".Filmstrip"
            data-segments={Jason.encode!(Enum.map(@all_segments, fn s -> %{start: s.start_time, end: s.end_time, text: s.text} end))}
          >
            <img
              :for={frame <- @frames}
              src={"/frames/#{frame.id}"}
              data-timestamp={frame.timestamp}
              class="h-16 w-auto rounded-sm cursor-crosshair shrink-0 opacity-80 hover:opacity-100 transition-opacity"
              loading="lazy"
            />
          </div>
          <div id="filmstrip-caption" class="mt-2 text-sm text-gray-600 min-h-[2.5rem] px-1">
            <span class="text-gray-400">Hover the filmstrip to see transcript at that moment</span>
          </div>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".Filmstrip">
          export default {
            mounted() {
              const segments = JSON.parse(this.el.dataset.segments)
              const caption = document.getElementById("filmstrip-caption")
              const imgs = this.el.querySelectorAll("img")

              imgs.forEach(img => {
                img.addEventListener("mouseenter", () => {
                  const ts = parseFloat(img.dataset.timestamp)
                  const seg = segments.find(s => ts >= s.start && ts < s.end)
                    || segments.reduce((closest, s) =>
                      Math.abs(s.start - ts) < Math.abs(closest.start - ts) ? s : closest
                    , segments[0])

                  if (seg) {
                    const mins = String(Math.floor(ts / 60)).padStart(2, "0")
                    const secs = String(Math.floor(ts % 60)).padStart(2, "0")
                    caption.innerHTML = `<span class="font-mono text-xs text-gray-400">${mins}:${secs}</span> <span class="ml-2">${seg.text}</span>`
                  }
                })
              })

              this.el.addEventListener("mouseleave", () => {
                caption.innerHTML = `<span class="text-gray-400">Hover the filmstrip to see transcript at that moment</span>`
              })
            }
          }
        </script>

        <form phx-change="filter" class="mb-6" id="transcript-filter-form">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search within this transcript..."
            phx-debounce="300"
            autofocus
            class="w-full px-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            id="transcript-filter"
          />
        </form>

        <div :if={@query != "" && @segments == []} class="text-center py-8 text-gray-400">
          No transcript matches for &ldquo;{@query}&rdquo;
        </div>

        <div :if={@segments == [] && @query == "" && @all_segments == []} class="text-center py-12 text-gray-400">
          No transcripts yet. Run classification on this video first.
        </div>

        <div class="space-y-1">
          <div
            :for={segment <- @segments}
            class="flex items-start gap-3 p-2 rounded hover:bg-gray-50 transition-colors"
          >
            <span class="shrink-0 font-mono text-xs text-gray-400 bg-gray-100 px-2 py-1 rounded mt-0.5 w-24 text-center">
              {format_timestamp(segment.start_time)}
            </span>
            <p class="text-sm text-gray-800 leading-relaxed flex-1">
              {segment.text}
            </p>
          </div>
        </div>

        <div :if={@query != "" && @segments != []} class="mt-4 text-xs text-gray-400">
          {length(@segments)} of {length(@all_segments)} segments match &ldquo;{@query}&rdquo;
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Pure functions

  defp filter_segments(segments, ""), do: segments
  defp filter_segments(segments, nil), do: segments

  defp filter_segments(segments, query) do
    downcased = String.downcase(query)

    Enum.filter(segments, fn segment ->
      String.contains?(String.downcase(segment.text), downcased)
    end)
  end

  defp format_timestamp(seconds) when is_float(seconds) do
    total = trunc(seconds)
    hours = div(total, 3600)
    mins = div(rem(total, 3600), 60)
    secs = rem(total, 60)

    if hours > 0 do
      "#{pad(hours)}:#{pad(mins)}:#{pad(secs)}"
    else
      "#{pad(mins)}:#{pad(secs)}"
    end
  end

  defp format_timestamp(_), do: "0:00"

  defp format_duration(nil), do: "unknown"

  defp format_duration(seconds) when is_float(seconds) do
    total = trunc(seconds)
    hours = div(total, 3600)
    minutes = div(rem(total, 3600), 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
