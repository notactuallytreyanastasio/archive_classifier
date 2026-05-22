defmodule ArchiveClassifierWeb.SearchLive do
  @moduledoc """
  Search transcripts by text — find the exact moment in any video.

  All state is encoded in the URL as `?q=<term>`, so search results are fully
  shareable: copy the URL, paste it, get the same results.
  """

  use ArchiveClassifierWeb, :live_view

  import Ecto.Query

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Classification.Transcript
  alias ArchiveClassifier.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Transcript Search")
     |> assign(:query, "")
     |> assign(:results, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")

    results =
      if String.length(String.trim(query)) >= 2 do
        search_transcripts(query)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/search?#{%{q: query}}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page_title="Transcript Search">
      <div class="os-content-padded" style="background: #ddd;">
        <header style="margin-bottom: 12px;">
          <h1 class="mac-header">Transcript Search</h1>
          <p class="mac-subtext" style="margin-top: 2px;">
            Search spoken words across all transcribed videos.
          </p>
        </header>

        <form phx-change="search" style="margin-bottom: 12px;">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search transcripts..."
            phx-debounce="300"
            autofocus
            class="mac-input"
            style="width: 100%; padding: 6px 8px; font-size: 14px;"
            id="transcript-search"
          />
        </form>

        <div :if={@query != "" && @results == []} class="mac-empty">
          No transcript matches found.
        </div>

        <div :if={@results != []}>
          <p class="mac-subtext" style="margin-bottom: 8px;">{length(@results)} matches</p>

          <div style="display: flex; flex-direction: column; gap: 6px;">
            <div
              :for={result <- @results}
              class="mac-card"
              style="padding: 8px 10px;"
            >
              <div style="display: flex; align-items: start; gap: 8px;">
                <img
                  src={"/thumbnails/#{result.video_id}"}
                  style="width: 72px; height: 50px; object-fit: cover; border: 1px solid #000; background: #808080; flex-shrink: 0;"
                  loading="lazy"
                />
                <div style="flex: 1; min-width: 0;">
                  <div class="mac-text" style="font-weight: bold; font-size: 11px;">
                    {String.trim(result.title)}
                  </div>
                  <div style="margin-top: 2px;">
                    <span class="mac-timestamp">
                      {format_timestamp(result.start_time)} — {format_timestamp(result.end_time)}
                    </span>
                    <span class="mac-subtext" style="margin-left: 6px;">{result.collection}</span>
                  </div>
                  <div class="mac-text" style="margin-top: 4px; line-height: 1.4;">
                    {result.text}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div :if={@results == [] && @query == ""} class="mac-empty" style="padding: 48px 16px;">
          <div class="mac-text" style="font-size: 14px; color: #666;">Type to search across all transcribed videos</div>
          <div class="mac-subtext" style="margin-top: 4px;">Results show the exact timestamp where the words appear</div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp search_transcripts(query) do
    term = "%#{query}%"

    from(t in Transcript,
      join: v in Video,
      on: t.video_id == v.id,
      where: ilike(t.text, ^term),
      select: %{
        text: t.text,
        start_time: t.start_time,
        end_time: t.end_time,
        title: v.title,
        archive_id: v.archive_id,
        collection: v.collection,
        video_id: v.id
      },
      order_by: [asc: v.title, asc: t.start_time],
      limit: 100
    )
    |> Repo.all()
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

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
