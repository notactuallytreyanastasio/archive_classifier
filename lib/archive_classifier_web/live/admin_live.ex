defmodule ArchiveClassifierWeb.AdminLive do
  @moduledoc """
  Admin dashboard for mass-enqueuing transcription jobs.
  Filter by duration, collection, search term, then enqueue matching videos.
  """

  use ArchiveClassifierWeb, :live_view

  import Ecto.Query

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Cache
  alias ArchiveClassifier.Repo

  @collections [
    {"all", "All Collections"},
    {"markpines", "Mark Pines Collection"},
    {"mp_ronwood", "Ron Wood"},
    {"markpines_fashion", "Fashion"},
    {"markpines_jacksonbrowne", "Jackson Browne"},
    {"markpines_musicindustry", "Music Industry"},
    {"markpines_rascals", "The Rascals"},
    {"diamondheadtapes", "Diamond Head Tapes"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(5_000, :refresh_jobs)

    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:collections, @collections)
     |> assign(:filters, %{search: "", collection: "all", min_duration: "", max_duration: "", status: "pending"})
     |> assign_matches()
     |> assign_jobs()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filters, normalize_filters(filters))
     |> assign_matches()}
  end

  @impl true
  def handle_event("enqueue_all", _params, socket) do
    video_ids = Enum.map(socket.assigns.matches, & &1.id)

    case video_ids do
      [] ->
        {:noreply, put_flash(socket, :error, "No videos to enqueue.")}

      ids ->
        count = Archive.enqueue_videos(ids)
        Cache.reload_all()

        {:noreply,
         socket
         |> assign(:stats, Cache.stats())
         |> assign_matches()
         |> put_flash(:info, "Enqueued #{count} videos for transcription.")}
    end
  end

  @impl true
  def handle_info(:refresh_jobs, socket) do
    {:noreply, assign_jobs(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page_title="Admin">
      <div class="os-content-padded" style="background: #ddd;">
        <header style="margin-bottom: 12px;">
          <h1 class="mac-header">Admin Dashboard</h1>
          <p class="mac-subtext" style="margin-top: 2px;">
            Mass-enqueue videos for transcription.
          </p>
        </header>

        <form phx-change="filter" id="admin-filters">
          <div class="mac-card" style="padding: 12px; margin-bottom: 12px;">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
              <div>
                <label class="mac-label">Min Duration (MM:SS)</label>
                <input
                  type="text"
                  name="filters[min_duration]"
                  value={@filters.min_duration}
                  placeholder="0:00"
                  class="mac-input"
                  style="width: 100%;"
                  id="min_duration"
                  phx-debounce="300"
                />
              </div>
              <div>
                <label class="mac-label">Max Duration (MM:SS)</label>
                <input
                  type="text"
                  name="filters[max_duration]"
                  value={@filters.max_duration}
                  placeholder="99:59"
                  class="mac-input"
                  style="width: 100%;"
                  id="max_duration"
                  phx-debounce="300"
                />
              </div>
            </div>

            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 8px;">
              <div>
                <label class="mac-label">Collection</label>
                <select name="filters[collection]" class="mac-select" style="width: 100%;" id="collection">
                  <option :for={{val, label} <- @collections} value={val} selected={val == @filters.collection}>
                    {label}
                  </option>
                </select>
              </div>
              <div>
                <label class="mac-label">Status</label>
                <select name="filters[status]" class="mac-select" style="width: 100%;" id="status">
                  <option value="pending" selected={@filters.status == "pending"}>Pending only</option>
                  <option value="" selected={@filters.status == ""}>All statuses</option>
                  <option value="classified" selected={@filters.status == "classified"}>Classified (re-process)</option>
                  <option value="failed" selected={@filters.status == "failed"}>Failed (retry)</option>
                </select>
              </div>
            </div>

            <div style="margin-top: 8px;">
              <label class="mac-label">Search</label>
              <input
                type="text"
                name="filters[search]"
                value={@filters.search}
                placeholder="Search title or description..."
                class="mac-input"
                style="width: 100%;"
                id="admin-search"
                phx-debounce="300"
              />
            </div>
          </div>
        </form>

        <div class="mac-card" style="padding: 12px; margin-bottom: 12px; display: flex; align-items: center; justify-content: space-between;">
          <span class="mac-text" style="font-weight: bold;">
            {length(@matches)} videos match
          </span>
          <button
            phx-click="enqueue_all"
            class="mac-btn mac-btn-primary"
            style="padding: 4px 16px;"
            disabled={@matches == []}
            id="enqueue-all-btn"
          >
            Enqueue All ({length(@matches)})
          </button>
        </div>

        <div class="mac-scroll-list" style="max-height: 50vh; padding: 0;">
          <div :if={@matches == []} class="mac-empty" style="padding: 16px;">
            No videos match the current filters.
          </div>
          <div
            :for={video <- @matches}
            style="display: flex; align-items: center; gap: 8px; padding: 4px 8px; border-bottom: 1px solid #999;"
          >
            <img
              src={"/thumbnails/#{video.id}"}
              style="width: 40px; height: 28px; object-fit: cover; border: 1px solid #000; background: #808080;"
              loading="lazy"
            />
            <span class="mac-text" style="flex: 1; font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
              {String.trim(video.title)}
            </span>
            <span class="mac-subtext" style="flex-shrink: 0; width: 50px; text-align: right;">
              {format_duration(video.duration)}
            </span>
            <span class={"mac-badge #{status_class(video.classification_status)}"} style="flex-shrink: 0;">
              {video.classification_status}
            </span>
          </div>
        </div>
        <%!-- Job Queue --%>
        <div class="mac-card" style="padding: 12px; margin-top: 12px;">
          <h2 class="mac-header" style="font-size: 13px; margin-bottom: 8px;">
            Job Queue
            <span class="mac-subtext" style="font-weight: normal; margin-left: 8px;">
              auto-refreshes every 5s
            </span>
          </h2>

          <div :if={@jobs == []} class="mac-empty" style="padding: 8px;">
            No jobs in queue.
          </div>

          <div class="mac-scroll-list" :if={@jobs != []} style="max-height: 30vh; padding: 0;">
            <div
              :for={job <- @jobs}
              style={"display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-bottom: 1px solid #999; background: #{job_bg(job.status)};"}
            >
              <span class={"mac-badge #{job_status_class(job.status)}"} style="flex-shrink: 0; width: 70px; text-align: center;">
                {job.status}
              </span>
              <span class="mac-text" style="flex: 1; font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                {job.module}.{job.function}
              </span>
              <span class="mac-subtext" style="flex-shrink: 0;">
                {if job.started_at, do: "started #{format_ago(job.started_at)}", else: "queued #{format_ago(job.queued_at)}"}
              </span>
              <span :if={job.attempts > 0} class="mac-subtext" style="flex-shrink: 0;">
                attempt {job.attempts}/{job.max_attempts}
              </span>
              <span :if={job.error} class="mac-subtext" style="flex-shrink: 0; color: red; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title={job.error}>
                {String.slice(job.error, 0, 80)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_jobs(socket) do
    jobs =
      from(j in Twerker.Job,
        order_by: [
          fragment("CASE status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END"),
          desc: j.inserted_at
        ],
        limit: 50
      )
      |> Repo.all()

    assign(socket, :jobs, jobs)
  end

  defp job_bg("running"), do: "#ffffcc"
  defp job_bg("queued"), do: "#fff"
  defp job_bg("failed"), do: "#ffcccc"
  defp job_bg("completed"), do: "#ccffcc"
  defp job_bg(_), do: "#fff"

  defp job_status_class("running"), do: "mac-badge-warn"
  defp job_status_class("queued"), do: ""
  defp job_status_class("completed"), do: "mac-badge-ok"
  defp job_status_class("failed"), do: "mac-badge-err"
  defp job_status_class(_), do: ""

  defp format_ago(nil), do: ""

  defp format_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  defp assign_matches(socket) do
    filters = socket.assigns.filters

    matches =
      Archive.list_videos_filtered(
        search: blank_to_nil(filters.search),
        collection: blank_to_nil(filters.collection),
        status: parse_status(filters.status),
        min_duration: parse_duration(filters.min_duration),
        max_duration: parse_duration(filters.max_duration)
      )

    assign(socket, :matches, matches)
  end

  defp normalize_filters(params) do
    %{
      search: Map.get(params, "search", ""),
      collection: Map.get(params, "collection", "all"),
      min_duration: Map.get(params, "min_duration", ""),
      max_duration: Map.get(params, "max_duration", ""),
      status: Map.get(params, "status", "pending")
    }
  end

  defp parse_duration(""), do: nil

  defp parse_duration(str) do
    case String.split(str, ":") do
      [m, s] ->
        with {mins, ""} <- Integer.parse(m),
             {secs, ""} <- Integer.parse(s) do
          (mins * 60 + secs) * 1.0
        else
          _ -> nil
        end

      [s] ->
        case Integer.parse(s) do
          {secs, ""} -> secs * 1.0
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_status(""), do: nil
  defp parse_status(s), do: String.to_existing_atom(s)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp format_duration(nil), do: "?"

  defp format_duration(seconds) when is_float(seconds) do
    total = trunc(seconds)
    m = div(total, 60)
    s = rem(total, 60)
    "#{m}:#{String.pad_leading(Integer.to_string(s), 2, "0")}"
  end

  defp status_class(:pending), do: ""
  defp status_class(:queued), do: "mac-badge-warn"
  defp status_class(:classifying), do: "mac-badge-info"
  defp status_class(:classified), do: "mac-badge-ok"
  defp status_class(:failed), do: "mac-badge-err"
  defp status_class(_), do: ""
end
