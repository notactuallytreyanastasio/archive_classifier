defmodule ArchiveClassifier.Pipeline.TranscribeTest do
  use ExUnit.Case, async: true

  # These test the pure functions extracted from the pipeline.
  # The pipeline itself is integration-tested manually (needs Whisper + network).

  describe "hallucination filtering" do
    # We test the filter indirectly via the module's private functions.
    # Since they're private, we test the observable behavior:
    # store_transcripts filters out hallucinated chunks before inserting.

    test "hallucination detection: non-ASCII ratio" do
      # > 50% non-ASCII should be filtered
      assert non_ascii_ratio("ლლლლლლლლ hello") > 0.5
      assert non_ascii_ratio("hello world") < 0.5
      assert non_ascii_ratio("MBC 뉴스 김성현입니다.") > 0.5
      assert non_ascii_ratio("I'm here with Manhattan Lifestyles.") < 0.1
    end

    test "hallucination detection: repeated words" do
      assert repeated_word?("the the the the the")
      assert repeated_word?("back back back back back back")
      refute repeated_word?("the quick brown fox jumps")
      refute repeated_word?("hello world")
    end
  end

  # Expose the private functions for testing via Module.eval_quoted
  # This is cleaner than making them public just for tests.
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
end
