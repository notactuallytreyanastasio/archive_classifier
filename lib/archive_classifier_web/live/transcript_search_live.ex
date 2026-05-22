defmodule ArchiveClassifierWeb.TranscriptSearchLive do
  @moduledoc """
  Interactive video explorer with frame scrubbing and transcript search.

  Three interactive zones:
  1. Frame viewer — hover to scrub through frames, caption shows spoken words
  2. Timeline slider — drag to any moment, frame + caption follow
  3. Searchable transcript — click any segment to jump there

  All state URL-encoded: `/videos/:id/transcript?q=guitar`
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

    # Pre-encode data for JS hook
    segment_data =
      Enum.map(all_segments, fn s ->
        %{start: s.start_time, end: s.end_time, text: s.text}
      end)

    {:ok,
     socket
     |> assign(:video, video)
     |> assign(:all_segments, all_segments)
     |> assign(:frames, frames)
     |> assign(:segment_data, segment_data)
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
      <div class="max-w-5xl mx-auto px-4 py-6">
        <div class="mb-4">
          <a href="/" class="text-sm text-blue-600 hover:text-blue-800">&larr; Back to catalog</a>
        </div>

        <%!-- Video explorer --%>
        <div
          id="video-explorer"
          phx-hook=".VideoExplorer"
          phx-update="ignore"
          data-frames={Jason.encode!(@frames)}
          data-segments={Jason.encode!(@segment_data)}
          data-duration={@video.duration || 0}
        >
          <%!-- Frame viewer --%>
          <div class="relative bg-black rounded-lg overflow-hidden cursor-crosshair" id="frame-container">
            <img
              :if={@frames != []}
              id="explorer-frame"
              src={"/frames/#{List.first(@frames).id}"}
              class="w-full h-auto max-h-[420px] object-contain mx-auto"
            />
            <div
              :if={@frames == []}
              class="w-full h-64 flex items-center justify-center text-gray-500"
            >
              No frames extracted yet
            </div>
          </div>

          <%!-- Caption --%>
          <div
            id="explorer-caption"
            class="mt-2 px-2 py-3 bg-gray-900 text-white text-center rounded-lg min-h-[3rem] flex items-center justify-center"
          >
            <span class="text-gray-500 text-sm">Hover the frame or drag the slider to explore</span>
          </div>

          <%!-- Timeline slider --%>
          <div class="mt-3 flex items-center gap-3">
            <span
              id="explorer-time"
              class="font-mono text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded w-16 text-center shrink-0"
            >
              00:00
            </span>
            <input
              type="range"
              id="explorer-slider"
              min="0"
              max={@video.duration || 0}
              step="0.5"
              value="0"
              class="flex-1 h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
            />
            <span class="text-xs text-gray-400 shrink-0">
              {format_duration(@video.duration)}
            </span>
          </div>
        </div>

        <%!-- Search + transcript --%>
        <div class="mt-6">
          <form phx-change="filter" class="mb-4" id="transcript-filter-form">
            <input
              type="text"
              name="q"
              value={@query}
              placeholder="Search spoken words..."
              phx-debounce="300"
              class="w-full px-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              id="transcript-filter"
            />
          </form>

          <div :if={@query != "" && @segments == []} class="text-center py-6 text-gray-400 text-sm">
            No matches for &ldquo;{@query}&rdquo;
          </div>

          <div :if={@segments == [] && @query == "" && @all_segments == []} class="text-center py-8 text-gray-400">
            No transcripts yet. Classify this video first.
          </div>

          <div id="transcript-segments" class="space-y-0.5">
            <button
              :for={segment <- @segments}
              type="button"
              data-start={segment.start_time}
              data-end={segment.end_time}
              class={[
                "transcript-segment w-full text-left flex items-start gap-3 px-3 py-2 rounded",
                "hover:bg-blue-50 transition-colors cursor-pointer"
              ]}
            >
              <span class="shrink-0 font-mono text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded mt-0.5 w-14 text-center">
                {format_timestamp(segment.start_time)}
              </span>
              <span class="text-sm text-gray-700 leading-relaxed flex-1">
                {segment.text}
              </span>
            </button>
          </div>

          <div :if={@query != "" && @segments != []} class="mt-3 text-xs text-gray-400">
            {length(@segments)} of {length(@all_segments)} segments
          </div>
        </div>

        <%!-- Colocated JS hook --%>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".VideoExplorer">
          export default {
            mounted() {
              const frames = JSON.parse(this.el.dataset.frames)
              const segments = JSON.parse(this.el.dataset.segments)
              const duration = parseFloat(this.el.dataset.duration) || 1

              if (frames.length === 0) return

              const img = document.getElementById("explorer-frame")
              const caption = document.getElementById("explorer-caption")
              const slider = document.getElementById("explorer-slider")
              const timeDisplay = document.getElementById("explorer-time")
              const frameContainer = document.getElementById("frame-container")

              // Preload all frame URLs for smooth scrubbing
              frames.forEach(f => {
                const preload = new Image()
                preload.src = `/frames/${f.id}`
              })

              const nearestFrame = (ts) => {
                let best = frames[0]
                for (const f of frames) {
                  if (Math.abs(f.timestamp - ts) < Math.abs(best.timestamp - ts)) best = f
                }
                return best
              }

              const segmentAt = (ts) => {
                for (const s of segments) {
                  if (ts >= s.start && ts < s.end) return s
                }
                // Find closest if between segments
                let closest = segments[0]
                for (const s of segments) {
                  if (Math.abs(s.start - ts) < Math.abs(closest.start - ts)) closest = s
                }
                return closest
              }

              const formatTime = (secs) => {
                const total = Math.floor(secs)
                const h = Math.floor(total / 3600)
                const m = Math.floor((total % 3600) / 60)
                const s = total % 60
                const pad = (n) => String(n).padStart(2, "0")
                return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
              }

              const update = (ts) => {
                const frame = nearestFrame(ts)
                if (img.dataset.currentFrame !== String(frame.id)) {
                  img.src = `/frames/${frame.id}`
                  img.dataset.currentFrame = String(frame.id)
                }

                const seg = segmentAt(ts)
                if (seg) {
                  caption.innerHTML = `<span class="text-base">${seg.text}</span>`
                } else {
                  caption.innerHTML = `<span class="text-gray-500 text-sm">...</span>`
                }

                timeDisplay.textContent = formatTime(ts)

                // Highlight active segment in transcript
                document.querySelectorAll(".transcript-segment").forEach(el => {
                  const start = parseFloat(el.dataset.start)
                  const end = parseFloat(el.dataset.end)
                  if (ts >= start && ts < end) {
                    el.classList.add("bg-blue-100")
                    el.classList.remove("hover:bg-blue-50")
                  } else {
                    el.classList.remove("bg-blue-100")
                    el.classList.add("hover:bg-blue-50")
                  }
                })
              }

              // Slider scrub
              slider.addEventListener("input", (e) => {
                update(parseFloat(e.target.value))
              })

              // Frame hover → scrub through frames by mouse position
              frameContainer.addEventListener("mousemove", (e) => {
                const rect = frameContainer.getBoundingClientRect()
                const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
                const ts = pct * duration
                update(ts)
                slider.value = ts
              })

              // Transcript segment click → jump to that time
              document.getElementById("transcript-segments")?.addEventListener("click", (e) => {
                const btn = e.target.closest("[data-start]")
                if (!btn) return
                const ts = parseFloat(btn.dataset.start)
                slider.value = ts
                update(ts)
                // Scroll frame into view
                frameContainer.scrollIntoView({ behavior: "smooth", block: "start" })
              })

              // Initialize with first frame
              update(0)
            }
          }
        </script>
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
