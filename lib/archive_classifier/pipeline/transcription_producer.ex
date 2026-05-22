defmodule ArchiveClassifier.Pipeline.TranscriptionProducer do
  @moduledoc """
  GenStage producer that manages the transcription queue.

  Videos are enqueued via `enqueue/1`. The producer dispatches
  them to supervised tasks with bounded concurrency (max 2 concurrent
  transcriptions to stay within memory limits).
  """

  use GenServer

  alias ArchiveClassifier.Pipeline.Transcribe

  require Logger

  @max_concurrent 2

  @type state :: %{
          queue: :queue.queue(integer()),
          active: MapSet.t(integer()),
          max_concurrent: pos_integer()
        }

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a video for transcription. Returns immediately.
  """
  @spec enqueue(integer()) :: :ok
  def enqueue(video_id) do
    GenServer.cast(__MODULE__, {:enqueue, video_id})
  end

  @doc """
  Returns the current queue status.
  """
  @spec status() :: %{queued: non_neg_integer(), active: non_neg_integer()}
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      queue: :queue.new(),
      active: MapSet.new(),
      max_concurrent: @max_concurrent
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, video_id}, state) do
    Logger.info("Enqueued video #{video_id} for transcription")

    state = %{state | queue: :queue.in(video_id, state.queue)}
    state = maybe_start_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed — demonitor and flush the :DOWN message
    Process.demonitor(ref, [:flush])

    {video_id, status} =
      case result do
        {:ok, _transcripts} -> {ref_to_video_id(ref, state), :ok}
        {:error, _reason} -> {ref_to_video_id(ref, state), :error}
      end

    if status == :ok do
      Logger.info("Transcription complete for video #{video_id}")
    end

    state = %{state | active: MapSet.delete(state.active, video_id)}
    state = maybe_start_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Transcription task crashed: #{inspect(reason)}")
    state = maybe_start_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      queued: :queue.len(state.queue),
      active: MapSet.size(state.active)
    }

    {:reply, reply, state}
  end

  # Internal

  defp maybe_start_next(state) do
    if MapSet.size(state.active) < state.max_concurrent do
      case :queue.out(state.queue) do
        {{:value, video_id}, rest} ->
          task =
            Task.Supervisor.async_nolink(
              ArchiveClassifier.Pipeline.TaskSupervisor,
              fn -> Transcribe.run(video_id) end
            )

          # Store the mapping from task ref to video_id in process dictionary
          # (simple approach for a bounded set)
          Process.put({:task_ref, task.ref}, video_id)

          Logger.info("Starting transcription for video #{video_id} (#{MapSet.size(state.active) + 1}/#{state.max_concurrent} active)")

          state = %{state | queue: rest, active: MapSet.put(state.active, video_id)}
          maybe_start_next(state)

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp ref_to_video_id(ref, _state) do
    Process.delete({:task_ref, ref}) || :unknown
  end
end
