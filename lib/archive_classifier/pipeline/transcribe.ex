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
  alias ArchiveClassifier.Pipeline.Dedup
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
    Logger.info("[pipeline] Starting: #{video.archive_id} (#{format_duration(video.duration)})")

    with :ok <- set_status(video, :classifying),
         {:ok, video_path} <- download(video),
         {:ok, audio_path} <- extract_audio(video_path, video),
         {:ok, result} <- transcribe(audio_path),
         {:ok, transcripts} <- store_transcripts(video, result),
         :ok <- extract_and_store_frames(video, video_path) do
      set_status(video, :classified)
      cleanup([video_path, audio_path])
      Cache.reload(video_id)
      Logger.info("[pipeline] Done: #{video.archive_id} — #{length(transcripts)} segments")
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
      Logger.info("[pipeline] Downloading #{archive_id}...")

      case Req.get(url,
             into: File.stream!(output_path),
             connect_timeout: :timer.seconds(30),
             receive_timeout: :timer.minutes(30),
             pool_timeout: :timer.minutes(5),
             retry: :transient,
             max_retries: 5,
             retry_delay: &exponential_backoff/1
           ) do
        {:ok, %{status: 200}} -> {:ok, output_path}
        {:ok, %{status: status}} -> {:error, "Download failed with status #{status}"}
        {:error, reason} ->
          Logger.error("[pipeline] Download error for #{archive_id}: #{inspect(reason)}")
          {:error, "Download failed: #{inspect(reason)}"}
      end
    end
  end

  # Exponential backoff: 1s, 2s, 4s, 8s, 16s
  defp exponential_backoff(retry_count) do
    delay = Integer.pow(2, retry_count) * 1_000
    Logger.info("[pipeline] Retry ##{retry_count + 1}, backing off #{div(delay, 1000)}s")
    delay
  end

  defp extract_audio(video_path, %Video{archive_id: archive_id}) do
    Logger.info("[pipeline] Extracting audio: #{archive_id}")
    audio_path = Path.join(@tmp_dir, "#{archive_id}.wav")
    Audio.extract_audio(video_path, audio_path)
  end

  defp transcribe(audio_path) do
    Logger.info("[pipeline] Sending to Whisper (this may take a while)...")
    Whisper.transcribe(audio_path)
  end

  defp store_transcripts(video, %{chunks: chunks}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      chunks
      |> Enum.reject(&hallucination?/1)
      |> Enum.map(fn chunk ->
        %{
          video_id: video.id,
          start_time: chunk.start_timestamp_seconds,
          end_time: chunk.end_timestamp_seconds,
          text: String.trim(chunk.text),
          inserted_at: now,
          updated_at: now
        }
      end)
      |> Enum.reject(fn entry -> entry.text == "" end)
      |> Dedup.merge_consecutive()

    filtered = length(chunks) - length(entries)

    if filtered > 0 do
      Logger.info("[pipeline] Filtered/deduped: #{length(chunks)} raw → #{length(entries)} kept")
    end

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

  # Whisper hallucinates on silence: repeated Unicode chars, single punctuation, etc.
  defp hallucination?(chunk) do
    text = String.trim(chunk.text)

    cond do
      # Empty or just punctuation
      String.length(text) < 2 -> true
      # Mostly non-Latin script (Georgian ლ, Arabic, etc.) — 50%+ non-ASCII
      non_ascii_ratio(text) > 0.5 -> true
      # Same word repeated 5+ times
      repeated_word?(text) -> true
      true -> false
    end
  end

  defp non_ascii_ratio(text) do
    chars = String.graphemes(text) |> Enum.reject(&(&1 == " "))
    total = length(chars)

    if total == 0 do
      0.0
    else
      non_ascii = Enum.count(chars, fn c -> byte_size(c) > 1 end)
      non_ascii / total
    end
  end

  defp repeated_word?(text) do
    words = String.split(text)

    if length(words) >= 5 do
      unique = words |> Enum.uniq() |> length()
      unique <= 2
    else
      false
    end
  end

  defp cleanup(paths) do
    Enum.each(paths, fn path ->
      File.rm(path)
    end)
  end

  defp format_duration(nil), do: "unknown"

  defp format_duration(seconds) when is_float(seconds) do
    total = trunc(seconds)
    m = div(total, 60)
    s = rem(total, 60)
    "#{m}m#{s}s"
  end
end
