defmodule ArchiveClassifier.ML.Whisper do
  @moduledoc """
  Bumblebee Whisper serving for audio transcription.

  Starts an Nx.Serving that accepts audio file paths and returns
  timestamped transcription chunks.
  """

  require Logger

  @type chunk :: %{text: String.t(), start_timestamp_seconds: float(), end_timestamp_seconds: float()}
  @type transcription :: %{chunks: [chunk()]}

  @default_model "openai/whisper-small"

  @doc """
  Returns the configured model repo, falling back to `"openai/whisper-small"`.
  """
  @spec model_repo() :: String.t()
  def model_repo do
    Application.get_env(:archive_classifier, :whisper_model, @default_model)
  end

  @doc """
  Returns the child spec for the Whisper Nx.Serving.
  Add this to your supervision tree to start the serving.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    repo = Keyword.get(opts, :model, model_repo())

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [repo]},
      type: :worker
    }
  end

  @doc """
  Starts the Whisper serving process.
  """
  @spec start_link(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(repo \\ model_repo()) do
    Logger.info("Loading Whisper model: #{repo}")

    {time_us, serving} =
      :timer.tc(fn ->
        {:ok, model_info} = Bumblebee.load_model({:hf, repo})
        {:ok, featurizer} = Bumblebee.load_featurizer({:hf, repo})
        {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, repo})
        {:ok, generation_config} = Bumblebee.load_generation_config({:hf, repo})

        Bumblebee.Audio.speech_to_text_whisper(
          model_info,
          featurizer,
          tokenizer,
          generation_config,
          defn_options: [compiler: EXLA],
          chunk_num_seconds: 30,
          timestamps: :segments
        )
      end)

    Logger.info("Whisper model loaded in #{div(time_us, 1_000_000)}s")

    Nx.Serving.start_link(serving: serving, name: __MODULE__, batch_timeout: 100)
  end

  @doc """
  Transcribe an audio file (16kHz mono WAV).
  Returns `{:ok, transcription}` with timestamped chunks.
  """
  @spec transcribe(String.t()) :: {:ok, transcription()} | {:error, term()}
  def transcribe(audio_path) do
    Logger.info("Transcribing: #{Path.basename(audio_path)}")

    {time_us, result} = :timer.tc(fn -> Nx.Serving.batched_run(__MODULE__, {:file, audio_path}) end)
    chunk_count = length(Map.get(result, :chunks, []))

    Logger.info("Transcription complete: #{chunk_count} segments in #{div(time_us, 1_000_000)}s")

    {:ok, result}
  rescue
    error -> {:error, error}
  end
end
