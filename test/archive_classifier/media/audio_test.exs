defmodule ArchiveClassifier.Media.AudioTest do
  use ExUnit.Case, async: true

  alias ArchiveClassifier.Media.Audio

  describe "available?/0" do
    test "returns a boolean" do
      result = Audio.available?()
      assert is_boolean(result)
    end

    test "returns true when Xav NIF is loaded" do
      assert Audio.available?()
    end
  end

  describe "extract_audio/2 typespec" do
    test "returns {:error, _} for a nonexistent file" do
      assert {:error, message} = Audio.extract_audio("/nonexistent/video.mp4", "/tmp/out.wav")
      assert is_binary(message)
    end
  end

  describe "duration/1 typespec" do
    test "returns {:error, _} for a nonexistent file" do
      assert {:error, message} = Audio.duration("/nonexistent/video.mp4")
      assert is_binary(message)
    end
  end
end
