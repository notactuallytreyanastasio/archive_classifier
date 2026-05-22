defmodule ArchiveClassifier.Pipeline.Dedup do
  @moduledoc """
  Merge consecutive transcript segments that have identical text.

  Whisper often gets stuck in loops, producing the same phrase for
  many consecutive 2-second windows. This module collapses those
  into a single segment spanning the full time range.
  """

  @type segment :: %{text: String.t(), start_time: float(), end_time: float()}

  @doc """
  Merges consecutive segments with identical text (after trimming).

  Returns a new list where runs of the same text are collapsed into
  one segment with the earliest start_time and latest end_time.
  """
  @spec merge_consecutive([segment()]) :: [segment()]
  def merge_consecutive([]), do: []
  def merge_consecutive([single]), do: [single]

  def merge_consecutive(segments) do
    segments
    |> Enum.reduce([], fn segment, acc ->
      case acc do
        [prev | rest] ->
          if same_text?(prev, segment) do
            merged = %{prev | end_time: segment.end_time}
            [merged | rest]
          else
            [segment | acc]
          end

        [] ->
          [segment]
      end
    end)
    |> Enum.reverse()
  end

  defp same_text?(a, b) do
    String.trim(a.text) == String.trim(b.text)
  end
end
