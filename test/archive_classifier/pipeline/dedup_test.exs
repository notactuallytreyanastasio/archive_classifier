defmodule ArchiveClassifier.Pipeline.DedupTest do
  use ExUnit.Case, async: true

  alias ArchiveClassifier.Pipeline.Dedup

  describe "merge_consecutive/1" do
    test "merges identical consecutive segments" do
      segments = [
        %{text: "I'm sorry, I'm sorry.", start_time: 46.0, end_time: 48.0},
        %{text: "I'm sorry, I'm sorry.", start_time: 48.0, end_time: 50.0},
        %{text: "I'm sorry, I'm sorry.", start_time: 50.0, end_time: 52.0},
        %{text: "Something different", start_time: 52.0, end_time: 54.0}
      ]

      result = Dedup.merge_consecutive(segments)

      assert length(result) == 2
      assert hd(result).start_time == 46.0
      assert hd(result).end_time == 52.0
      assert hd(result).text == "I'm sorry, I'm sorry."
    end

    test "leaves non-consecutive duplicates alone" do
      segments = [
        %{text: "hello", start_time: 0.0, end_time: 2.0},
        %{text: "world", start_time: 2.0, end_time: 4.0},
        %{text: "hello", start_time: 4.0, end_time: 6.0}
      ]

      result = Dedup.merge_consecutive(segments)
      assert length(result) == 3
    end

    test "handles empty list" do
      assert Dedup.merge_consecutive([]) == []
    end

    test "handles single segment" do
      segments = [%{text: "solo", start_time: 0.0, end_time: 5.0}]
      assert Dedup.merge_consecutive(segments) == segments
    end

    test "normalizes whitespace before comparing" do
      segments = [
        %{text: " I'm sorry. ", start_time: 0.0, end_time: 2.0},
        %{text: "I'm sorry.", start_time: 2.0, end_time: 4.0},
        %{text: "  I'm sorry.  ", start_time: 4.0, end_time: 6.0}
      ]

      result = Dedup.merge_consecutive(segments)
      assert length(result) == 1
      assert hd(result).end_time == 6.0
    end

    test "merges long runs of repetition" do
      segments =
        for i <- 0..19 do
          %{text: "I'm sorry, I'm sorry.", start_time: i * 2.0, end_time: (i + 1) * 2.0}
        end

      result = Dedup.merge_consecutive(segments)
      assert length(result) == 1
      assert hd(result).start_time == 0.0
      assert hd(result).end_time == 40.0
    end
  end
end
