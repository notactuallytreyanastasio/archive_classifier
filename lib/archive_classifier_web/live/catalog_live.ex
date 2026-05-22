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
     |> assign(:transcribed_only, true)
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
  def handle_event("toggle_transcribed", _params, socket) do
    {:noreply,
     socket
     |> assign(:transcribed_only, !socket.assigns.transcribed_only)
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

    # Enqueue via Twerker — persisted to Postgres, picked up by GenStage consumers
    Twerker.enqueue(ArchiveClassifier.Pipeline.Transcribe, :run, [video_id])

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
  def handle_event("reclassify", %{"id" => id}, socket) do
    video_id = String.to_integer(id)

    # Clear old transcripts and frames
    import Ecto.Query

    ArchiveClassifier.Repo.delete_all(
      from(t in ArchiveClassifier.Classification.Transcript, where: t.video_id == ^video_id)
    )

    ArchiveClassifier.Repo.delete_all(
      from(f in ArchiveClassifier.Classification.VideoFrame, where: f.video_id == ^video_id)
    )

    # Reset and re-enqueue via Twerker
    video = Archive.get_video!(video_id)
    Twerker.enqueue(ArchiveClassifier.Pipeline.Transcribe, :run, [video_id])

    case Archive.queue_for_classification(video) do
      {:ok, _updated} ->
        Cache.reload(video_id)

        {:noreply,
         socket
         |> assign(:stats, Cache.stats())
         |> assign_videos()
         |> put_flash(:info, "Reclassifying #{String.trim(video.title)}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to reclassify.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page_title="Archive Catalog">
      <div class="os-content-padded" style="background: #ddd;">
        <header style="margin-bottom: 12px;">
          <h1 class="mac-header">Archive Catalog</h1>
          <p class="mac-subtext" style="margin-top: 2px;">
            {format_number(@stats.total)} videos &middot;
            {format_number(@stats.pending)} pending &middot;
            {format_number(@stats.queued)} queued &middot;
            {format_number(@stats.classified)} classified
          </p>
        </header>

        <div style="display: flex; gap: 8px; margin-bottom: 12px;">
          <form phx-change="search" phx-submit="search" style="flex: 1;">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search by title or description..."
              phx-debounce="300"
              class="mac-input"
              style="width: 100%;"
              id="catalog-search"
            />
          </form>

          <form phx-change="sort">
            <select
              name="sort"
              class="mac-select"
              id="catalog-sort"
            >
              <option :for={{val, label} <- @sort_options} value={val} selected={val == @sort}>
                {label}
              </option>
            </select>
          </form>

          <label style="display: flex; align-items: center; gap: 4px; cursor: pointer; white-space: nowrap;" class="mac-text">
            <input
              type="checkbox"
              checked={@transcribed_only}
              phx-click="toggle_transcribed"
              id="transcribed-only"
            /> Transcribed only
          </label>
        </div>

        <%!-- Collection overview --%>
        <div :if={@selected_collection == nil}>
          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 8px;">
            <button
              :for={col <- @collections}
              phx-click="select_collection"
              phx-value-collection={col.name}
              class="mac-card"
              style="text-align: left; padding: 0; cursor: pointer; display: block;"
            >
              <div style="display: flex; align-items: start; gap: 8px; padding: 8px;">
                <img
                  src={thumbnail_url(col.sample_id)}
                  style="width: 64px; height: 48px; object-fit: cover; border: 1px solid #000; background: #808080;"
                  loading="lazy"
                />
                <div style="flex: 1; min-width: 0;">
                  <div class="mac-text" style="font-weight: bold;">
                    {format_collection(col.name)}
                  </div>
                  <div class="mac-subtext" style="margin-top: 2px;">
                    {col.count} videos &middot; {format_total_duration(col.total_duration)}
                  </div>
                </div>
              </div>
            </button>
          </div>
        </div>

        <%!-- Drilled-in collection view --%>
        <div :if={@selected_collection != nil}>
          <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
            <button
              phx-click="back_to_collections"
              class="mac-btn"
              style="font-size: 11px; padding: 2px 10px;"
            >
              &larr; Back
            </button>
            <span class="mac-header" style="font-size: 13px;">
              {format_collection(@selected_collection)}
            </span>
            <span class="mac-subtext">{length(@videos)} videos</span>
          </div>

          <div :if={@videos == []} class="mac-empty">
            No videos found.
          </div>

          <div style="display: grid; gap: 8px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));">
            <div
              :for={video <- @videos}
              id={"video-#{video.id}"}
              class="mac-card group"
              style="overflow: visible; position: relative;"
            >
              <img
                src={thumbnail_url(video.id)}
                class="mac-thumb"
                style="width: 100%; height: 120px; object-fit: cover;"
                loading="lazy"
              />
              <div style="padding: 6px 8px;">
                <div class="mac-text" style="font-weight: bold; font-size: 11px; cursor: default;">
                  {String.trim(video.title)}
                </div>
                <div
                  :if={video.description && String.trim(video.description) != String.trim(video.title)}
                  class="mac-tooltip"
                  style="position: absolute; z-index: 10; left: 4px; right: 4px; bottom: 100%; margin-bottom: 4px; opacity: 0; visibility: hidden; transition: opacity 0.15s; pointer-events: none; max-height: 120px; overflow: hidden;"
                >
                  {strip_html(video.description)}
                </div>
                <div class="mac-subtext" style="margin-top: 2px;">
                  {format_duration(video.duration)}
                </div>

                <div :if={video.tags != []} style="margin-top: 4px;">
                  <span :for={tag <- video.tags} class="mac-tag">
                    {tag}
                  </span>
                </div>

                <hr class="mac-divider" style="margin-top: 6px;" />
                <div style="display: flex; align-items: center; justify-content: space-between; margin-top: 4px; flex-wrap: wrap; gap: 4px;">
                  <span class={["mac-badge", status_badge_class(video.classification_status)]}>
                    {video.classification_status}
                  </span>

                  <button
                    :if={video.classification_status == :pending}
                    phx-click="classify"
                    phx-value-id={video.id}
                    class="mac-btn mac-btn-primary"
                    style="font-size: 10px; padding: 2px 10px;"
                  >
                    Classify
                  </button>

                  <div style="display: flex; gap: 4px;">
                    <a
                      href={"https://archive.org/details/#{video.archive_id}"}
                      target="_blank"
                      class="mac-btn"
                      style="font-size: 10px; padding: 2px 10px; text-decoration: none; color: #000;"
                    >
                      Watch ↗
                    </a>

                    <.link
                      :if={video.classification_status in [:classified, :failed]}
                      navigate={~p"/videos/#{video.id}/transcript"}
                      class="mac-btn"
                      style="font-size: 10px; padding: 2px 10px; text-decoration: none; color: #000;"
                    >
                      Transcript
                    </.link>

                    <button
                      :if={video.classification_status in [:classified, :failed]}
                      phx-click="reclassify"
                      phx-value-id={video.id}
                      class="mac-btn"
                      style="font-size: 10px; padding: 2px 10px;"
                    >
                      Redo
                    </button>
                  </div>
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
    videos = filtered_videos(socket.assigns)

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

  defp assign_videos(%{assigns: %{selected_collection: col, sort: sort}} = socket) do
    videos =
      filtered_videos(socket.assigns)
      |> Enum.filter(&(&1.collection == col))
      |> sort_videos(sort)

    assign(socket, :videos, videos)
  end

  defp filtered_videos(%{search: search, transcribed_only: true}) do
    Cache.search(search)
    |> Enum.filter(&(&1.classification_status == :classified))
  end

  defp filtered_videos(%{search: search}) do
    Cache.search(search)
  end

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

  defp status_badge_class(:pending), do: "mac-badge-pending"
  defp status_badge_class(:queued), do: "mac-badge-queued"
  defp status_badge_class(:classifying), do: "mac-badge-classifying"
  defp status_badge_class(:classified), do: "mac-badge-classified"
  defp status_badge_class(:failed), do: "mac-badge-failed"
  defp status_badge_class(_), do: "mac-badge-pending"
end
