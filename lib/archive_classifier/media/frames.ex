defmodule ArchiveClassifier.Media.Frames do
  @moduledoc """
  Extract frames from video at regular intervals.

  ## TODO: Replace with Xav NIF

  This module shells out to FFmpeg CLI for JPEG frame extraction.
  This is a stopgap — we want all media operations through Xav NIFs.
  Xav 0.11 supports video decoding but not direct JPEG encoding.
  Options:
  - Contribute JPEG export to upstream Xav
  - Fork Xav and add it ourselves
  - Use Xav to decode frames → Nx tensor → Image library for JPEG encoding

  Track: https://github.com/elixir-webrtc/xav
  """

  require Logger

  @default_interval 10.0

  @doc """
  Extracts one JPEG frame every `interval` seconds from a video file.
  Returns `{:ok, [{timestamp, jpeg_binary}]}` or `{:error, reason}`.
  """
  @spec extract_frames(String.t(), float()) :: {:ok, [{float(), binary()}]} | {:error, String.t()}
  def extract_frames(video_path, interval \\ @default_interval) do
    tmp_dir = Path.join(System.tmp_dir!(), "archive_classifier_frames_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    args = [
      "-i", video_path,
      "-vf", "fps=1/#{interval},scale=320:-1",
      "-q:v", "5",
      "-y",
      Path.join(tmp_dir, "frame_%05d.jpg")
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        frames =
          tmp_dir
          |> File.ls!()
          |> Enum.sort()
          |> Enum.with_index()
          |> Enum.map(fn {filename, index} ->
            timestamp = index * interval
            {:ok, jpeg} = File.read(Path.join(tmp_dir, filename))
            {timestamp, jpeg}
          end)

        File.rm_rf!(tmp_dir)
        Logger.info("Extracted #{length(frames)} frames at #{interval}s intervals")
        {:ok, frames}

      {output, _code} ->
        File.rm_rf!(tmp_dir)
        {:error, "Frame extraction failed: #{String.slice(output, 0, 500)}"}
    end
  end
end
