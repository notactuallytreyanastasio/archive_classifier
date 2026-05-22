defmodule ArchiveClassifier.ML.Whisper do
  @moduledoc """
  Bumblebee Whisper serving for audio transcription.

  Starts an Nx.Serving that accepts audio file paths and returns
  timestamped transcription chunks.
  """

  @type chunk :: %{text: String.t(), start_timestamp_seconds: float(), end_timestamp_seconds: float()}
  @type transcription :: %{chunks: [chunk()]}

  @model_repo "openai/whisper-small"

  @doc """
  Returns the child spec for the Whisper Nx.Serving.
  Add this to your supervision tree to start the serving.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    model_repo = Keyword.get(opts, :model, @model_repo)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [model_repo]},
      type: :worker
    }
  end

  @doc """
  Starts the Whisper serving process.
  """
  @spec start_link(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(model_repo \\ @model_repo) do
    {:ok, model_info} = Bumblebee.load_model({:hf, model_repo})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, model_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, model_repo})

    serving =
      Bumblebee.Audio.speech_to_text_whisper(
        model_info,
        featurizer,
        tokenizer,
        generation_config,
        defn_options: [compiler: EXLA],
        timestamps: :segments
      )

    Nx.Serving.start_link(serving: serving, name: __MODULE__, batch_timeout: 100)
  end

  @doc """
  Transcribe an audio file (16kHz mono WAV).
  Returns `{:ok, transcription}` with timestamped chunks.
  """
  @spec transcribe(String.t()) :: {:ok, transcription()} | {:error, term()}
  def transcribe(audio_path) do
    {:ok, audio_binary} = File.read(audio_path)

    result = Nx.Serving.batched_run(__MODULE__, {:file, audio_binary})

    {:ok, result}
  rescue
    error -> {:error, error}
  end
end
