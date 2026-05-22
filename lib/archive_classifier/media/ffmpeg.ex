defmodule ArchiveClassifier.Media.FFmpeg do
  @moduledoc """
  FFmpeg wrappers for audio extraction and frame sampling.
  Pure functions that return commands or process results — no side effects beyond System.cmd.
  """

  @doc """
  Extracts audio from a video file as 16kHz mono WAV (Whisper's expected format).
  Returns `{:ok, output_path}` or `{:error, reason}`.
  """
  @spec extract_audio(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_audio(video_path, output_path) do
    args = [
      "-i", video_path,
      "-vn",
      "-acodec", "pcm_s16le",
      "-ar", "16000",
      "-ac", "1",
      "-y",
      output_path
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, output_path}
      {output, _code} -> {:error, "FFmpeg failed: #{String.slice(output, 0, 500)}"}
    end
  end

  @doc """
  Returns the duration of a media file in seconds.
  """
  @spec duration(String.t()) :: {:ok, float()} | {:error, String.t()}
  def duration(path) do
    args = [
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Float.parse(String.trim(output)) do
          {seconds, _} -> {:ok, seconds}
          :error -> {:error, "Could not parse duration: #{output}"}
        end

      {output, _code} ->
        {:error, "ffprobe failed: #{String.slice(output, 0, 500)}"}
    end
  end

  @doc """
  Checks if ffmpeg is available on the system.
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd("ffmpeg", ["-version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
  end
end
