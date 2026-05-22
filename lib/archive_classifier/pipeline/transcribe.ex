defmodule ArchiveClassifier.Pipeline.Transcribe do
  @moduledoc """
  Transcription pipeline for a single video.

  Downloads the video, extracts audio, runs Whisper, stores transcript
  segments, then cleans up the downloaded files.
  """

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Cache
  alias ArchiveClassifier.Classification.Transcript
  alias ArchiveClassifier.Classification.VideoFrame
  alias ArchiveClassifier.Media.Audio
  alias ArchiveClassifier.Media.Frames
  alias ArchiveClassifier.ML.Whisper
  alias ArchiveClassifier.Repo

  require Logger

  @tmp_dir Path.join(System.tmp_dir!(), "archive_classifier")

  @doc """
  Run the full transcription pipeline for a video.
  Updates status as it progresses: queued → classifying → classified (or failed).
  """
  @spec run(integer()) :: {:ok, [Transcript.t()]} | {:error, term()}
  def run(video_id) do
    video = Archive.get_video!(video_id)

    with :ok <- set_status(video, :classifying),
         {:ok, video_path} <- download(video),
         {:ok, audio_path} <- extract_audio(video_path, video),
         {:ok, result} <- transcribe(audio_path),
         {:ok, transcripts} <- store_transcripts(video, result),
         :ok <- extract_and_store_frames(video, video_path) do
      set_status(video, :classified)
      cleanup([video_path, audio_path])
      Cache.reload(video_id)
      Logger.info("Transcribed #{video.archive_id}: #{length(transcripts)} segments")
      {:ok, transcripts}
    else
      {:error, reason} = error ->
        set_status(video, :failed)
        Cache.reload(video_id)
        Logger.error("Transcription failed for #{video.archive_id}: #{inspect(reason)}")
        error
    end
  end

  defp set_status(video, status) do
    video
    |> Video.changeset(%{classification_status: status})
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp download(%Video{archive_id: archive_id, primary_video_url: url}) do
    File.mkdir_p!(@tmp_dir)
    output_path = Path.join(@tmp_dir, "#{archive_id}.mp4")

    if File.exists?(output_path) do
      {:ok, output_path}
    else
      Logger.info("Downloading #{archive_id}...")

      case Req.get(url, into: File.stream!(output_path), receive_timeout: :timer.minutes(30)) do
        {:ok, %{status: 200}} -> {:ok, output_path}
        {:ok, %{status: status}} -> {:error, "Download failed with status #{status}"}
        {:error, reason} -> {:error, "Download failed: #{inspect(reason)}"}
      end
    end
  end

  defp extract_audio(video_path, %Video{archive_id: archive_id}) do
    audio_path = Path.join(@tmp_dir, "#{archive_id}.wav")
    Audio.extract_audio(video_path, audio_path)
  end

  defp transcribe(audio_path) do
    Whisper.transcribe(audio_path)
  end

  defp store_transcripts(video, %{chunks: chunks}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(chunks, fn chunk ->
        %{
          video_id: video.id,
          start_time: chunk.start_timestamp_seconds,
          end_time: chunk.end_timestamp_seconds,
          text: chunk.text,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, transcripts} =
      Repo.insert_all(Transcript, entries, returning: true)

    {:ok, transcripts}
  end

  defp extract_and_store_frames(video, video_path) do
    case Frames.extract_frames(video_path) do
      {:ok, frames} ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        entries =
          Enum.map(frames, fn {timestamp, jpeg} ->
            %{
              video_id: video.id,
              timestamp: timestamp,
              image: jpeg,
              inserted_at: now,
              updated_at: now
            }
          end)

        Repo.insert_all(VideoFrame, entries)
        Logger.info("Stored #{length(entries)} frames for #{video.archive_id}")
        :ok

      {:error, reason} ->
        # Frames are nice-to-have — don't fail the whole pipeline
        Logger.warning("Frame extraction failed for #{video.archive_id}: #{reason}")
        :ok
    end
  end

  defp cleanup(paths) do
    Enum.each(paths, fn path ->
      File.rm(path)
    end)
  end
end
