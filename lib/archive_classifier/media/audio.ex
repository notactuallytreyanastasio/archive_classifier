defmodule ArchiveClassifier.Media.Audio do
  @moduledoc """
  Audio extraction using Xav NIF bindings.
  Replaces the previous FFmpeg CLI approach with in-process decoding.
  """

  @sample_rate 16_000
  @channels 1
  @bits_per_sample 16

  @doc """
  Extracts audio from a media file as 16kHz mono 16-bit PCM WAV (Whisper's expected format).
  Returns `{:ok, output_path}` or `{:error, reason}`.
  """
  @spec extract_audio(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_audio(input_path, output_path) do
    reader =
      Xav.Reader.new!(input_path,
        read: :audio,
        out_format: :s16,
        out_sample_rate: @sample_rate,
        out_channels: @channels
      )

    pcm_data =
      reader
      |> stream_frames()
      |> Enum.reduce(<<>>, fn frame, acc -> acc <> frame.data end)

    wav_binary = encode_wav(pcm_data)
    File.write!(output_path, wav_binary)

    {:ok, output_path}
  rescue
    e -> {:error, "Audio extraction failed: #{Exception.message(e)}"}
  end

  @doc """
  Returns the duration of a media file in seconds.
  """
  @spec duration(String.t()) :: {:ok, float()} | {:error, String.t()}
  def duration(path) do
    reader = Xav.Reader.new!(path, read: :audio)
    # Xav returns duration from FFmpeg's AVFormatContext in microseconds
    {:ok, reader.duration / 1_000_000}
  rescue
    e -> {:error, "Could not read duration: #{Exception.message(e)}"}
  end

  @doc """
  Checks if Xav is available (the NIF is loaded and functional).
  """
  @spec available?() :: boolean()
  def available? do
    _ = Xav.sample_formats()
    true
  rescue
    _ -> false
  end

  # Stream all audio frames from a reader until EOF.
  defp stream_frames(reader) do
    Stream.unfold(reader, fn r ->
      case Xav.Reader.next_frame(r) do
        {:ok, frame} -> {frame, r}
        {:error, :eof} -> nil
      end
    end)
  end

  # Encode raw PCM data as a WAV file (RIFF header + data).
  defp encode_wav(pcm_data) do
    data_size = byte_size(pcm_data)
    byte_rate = @sample_rate * @channels * div(@bits_per_sample, 8)
    block_align = @channels * div(@bits_per_sample, 8)

    <<
      # RIFF header
      "RIFF",
      data_size + 36::little-32,
      "WAVE",
      # fmt sub-chunk
      "fmt ",
      16::little-32,
      1::little-16,
      @channels::little-16,
      @sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      @bits_per_sample::little-16,
      # data sub-chunk
      "data",
      data_size::little-32,
      pcm_data::binary
    >>
  end
end
