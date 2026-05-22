defmodule ArchiveClassifier.Pipeline.Supervisor do
  @moduledoc """
  Supervisor for the transcription pipeline.

  Houses the Task.Supervisor for pipeline work and the
  TranscriptionProducer GenStage.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Task.Supervisor, name: ArchiveClassifier.Pipeline.TaskSupervisor},
      ArchiveClassifier.Pipeline.TranscriptionProducer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
