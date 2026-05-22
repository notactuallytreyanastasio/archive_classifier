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
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <header class="mb-6">
          <h1 class="text-2xl font-semibold text-gray-900">Transcript Search</h1>
          <p class="mt-1 text-sm text-gray-500">
            Search spoken words across all transcribed videos. Results link to the exact timestamp.
          </p>
        </header>

        <form phx-change="search" class="mb-8">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search transcripts..."
            phx-debounce="300"
            autofocus
            class="w-full px-4 py-3 text-lg border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            id="transcript-search"
          />
        </form>

        <div :if={@query != "" && @results == []} class="text-center py-12 text-gray-400">
          No transcript matches found.
        </div>

        <div :if={@results != []} class="space-y-4">
          <p class="text-sm text-gray-500 mb-4">{length(@results)} matches</p>

          <div
            :for={result <- @results}
            class="p-4 bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            <div class="flex items-start gap-4">
              <img
                src={"/thumbnails/#{result.video_id}"}
                class="w-20 h-14 object-cover rounded bg-gray-100 shrink-0"
                loading="lazy"
              />
              <div class="flex-1 min-w-0">
                <h3 class="text-sm font-semibold text-gray-900">
                  {String.trim(result.title)}
                </h3>
                <p class="text-xs text-gray-500 mt-0.5">
                  <span class="font-mono bg-gray-100 px-1.5 py-0.5 rounded">
                    {format_timestamp(result.start_time)} — {format_timestamp(result.end_time)}
                  </span>
                  <span class="ml-2">{result.collection}</span>
                </p>
                <p class="text-sm text-gray-700 mt-2 leading-relaxed">
                  {result.text}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div :if={@results == [] && @query == ""} class="text-center py-16 text-gray-300">
          <p class="text-lg">Type to search across all transcribed videos</p>
          <p class="text-sm mt-2">Results show the exact timestamp where the words appear</p>
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
