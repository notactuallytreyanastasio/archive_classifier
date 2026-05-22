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
  alias ArchiveClassifier.Pipeline.Dedup
  alias ArchiveClassifier.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    video = Archive.get_video!(String.to_integer(id))

    all_segments =
      Transcript
      |> where([t], t.video_id == ^video.id)
      |> order_by([t], asc: t.start_time)
      |> Repo.all()
      |> Dedup.merge_consecutive()

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
    <Layouts.app flash={@flash} page_title={String.trim(@video.title)}>
      <div class="os-content-padded" style="background: #ddd;">
        <div style="margin-bottom: 8px;">
          <a href="/" class="mac-link" style="font-size: 11px;">&larr; Back to catalog</a>
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
          <div style="position: relative; background: #000; border: 2px inset #fff; overflow: hidden; cursor: crosshair;" id="frame-container">
            <img
              :if={@frames != []}
              id="explorer-frame"
              src={"/frames/#{List.first(@frames).id}"}
              style="width: 100%; height: auto; max-height: 420px; object-fit: contain; margin: 0 auto; display: block;"
            />
            <div
              :if={@frames == []}
              class="mac-empty"
              style="height: 200px; display: flex; align-items: center; justify-content: center; color: #999;"
            >
              No frames extracted yet
            </div>
          </div>

          <%!-- Caption --%>
          <div
            id="explorer-caption"
            class="mac-info-box"
            style="margin-top: 4px; text-align: center; min-height: 2.5rem; display: flex; align-items: center; justify-content: center;"
          >
            <span class="mac-subtext">Hover the frame or drag the slider to explore</span>
          </div>

          <%!-- Timeline slider --%>
          <div style="margin-top: 6px; display: flex; align-items: center; gap: 8px;">
            <button
              id="play-btn"
              class="mac-btn"
              style="padding: 2px 10px; font-size: 12px; flex-shrink: 0; width: 44px;"
            >
              ▶
            </button>
            <span
              id="explorer-time"
              class="mac-timestamp"
              style="width: 52px; text-align: center; flex-shrink: 0;"
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
              class="mac-slider"
              style="flex: 1;"
            />
            <span class="mac-subtext" style="flex-shrink: 0;">
              {format_duration(@video.duration)}
            </span>
          </div>
        </div>

        <%!-- Search + transcript --%>
        <div style="margin-top: 12px;">
          <form phx-change="filter" style="margin-bottom: 8px;" id="transcript-filter-form">
            <input
              type="text"
              name="q"
              value={@query}
              placeholder="Search spoken words..."
              phx-debounce="300"
              class="mac-input"
              style="width: 100%;"
              id="transcript-filter"
            />
          </form>

          <div :if={@query != "" && @segments == []} class="mac-empty" style="padding: 16px;">
            No matches for &ldquo;{@query}&rdquo;
          </div>

          <div :if={@segments == [] && @query == "" && @all_segments == []} class="mac-empty">
            No transcripts yet. Classify this video first.
          </div>

          <div id="transcript-segments" class="mac-scroll-list" style="max-height: 50vh; padding: 0;">
            <button
              :for={segment <- @segments}
              type="button"
              data-start={segment.start_time}
              data-end={segment.end_time}
              class="transcript-segment mac-segment"
              style="width: 100%; text-align: left; display: flex; align-items: start; gap: 8px; padding: 4px 8px; border: none; background: transparent;"
            >
              <span class="mac-timestamp" style="flex-shrink: 0; margin-top: 2px;">
                {format_timestamp(segment.start_time)}
              </span>
              <span class="mac-text" style="flex: 1; line-height: 1.4;">
                {segment.text}
              </span>
            </button>
          </div>

          <div :if={@query != "" && @segments != []} class="mac-subtext" style="margin-top: 4px;">
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
                  const active = ts >= start && ts < end
                  el.style.background = active ? "#000" : "transparent"
                  el.querySelectorAll("*").forEach(child => {
                    child.style.color = active ? "#fff" : ""
                    child.style.background = active ? "transparent" : ""
                  })
                })
              }

              // Slider scrub
              slider.addEventListener("input", (e) => {
                update(parseFloat(e.target.value))
              })

              // Frame click+drag → scrub through frames by mouse position
              let isDragging = false
              frameContainer.addEventListener("mousedown", (e) => {
                isDragging = true
                const rect = frameContainer.getBoundingClientRect()
                const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
                const ts = pct * duration
                update(ts)
                slider.value = ts
              })
              frameContainer.addEventListener("mousemove", (e) => {
                if (!isDragging) return
                const rect = frameContainer.getBoundingClientRect()
                const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
                const ts = pct * duration
                update(ts)
                slider.value = ts
              })
              document.addEventListener("mouseup", () => { isDragging = false })

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

              // Play/pause — auto-advance through frames
              const playBtn = document.getElementById("play-btn")
              let playInterval = null
              let currentFrameIdx = 0

              playBtn.addEventListener("click", () => {
                if (playInterval) {
                  // Pause
                  clearInterval(playInterval)
                  playInterval = null
                  playBtn.textContent = "▶"
                } else {
                  // Find starting frame index closest to current slider position
                  const currentTs = parseFloat(slider.value)
                  currentFrameIdx = frames.reduce((bestIdx, f, idx) =>
                    Math.abs(f.timestamp - currentTs) < Math.abs(frames[bestIdx].timestamp - currentTs) ? idx : bestIdx
                  , 0)

                  playBtn.textContent = "⏸"
                  playInterval = setInterval(() => {
                    currentFrameIdx++
                    if (currentFrameIdx >= frames.length) {
                      currentFrameIdx = 0  // Loop
                    }
                    const ts = frames[currentFrameIdx].timestamp
                    slider.value = ts
                    update(ts)

                    // Auto-scroll active segment into view
                    const active = document.querySelector(".transcript-segment[style*='background']")
                    if (active) active.scrollIntoView({ behavior: "smooth", block: "nearest" })
                  }, 3000)
                }
              })

              // Stop playback on manual interaction
              slider.addEventListener("input", () => {
                if (playInterval) {
                  clearInterval(playInterval)
                  playInterval = null
                  playBtn.textContent = "▶"
                }
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
