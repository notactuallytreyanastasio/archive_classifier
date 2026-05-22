defmodule ArchiveClassifier.Archive.VideoTest do
  use ArchiveClassifier.DataCase, async: true

  alias ArchiveClassifier.Archive.Video

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset =
        Video.changeset(%Video{}, %{
          archive_id: "mp_test_video",
          title: "Test Video",
          primary_video_url: "https://archive.org/download/test/test.mp4",
          collection: "markpines",
          files_json: "[]"
        })

      assert changeset.valid?
    end

    test "invalid without archive_id" do
      changeset =
        Video.changeset(%Video{}, %{
          title: "Test",
          primary_video_url: "https://example.com/test.mp4",
          collection: "markpines",
          files_json: "[]"
        })

      refute changeset.valid?
      assert %{archive_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without title" do
      changeset =
        Video.changeset(%Video{}, %{
          archive_id: "test",
          primary_video_url: "https://example.com/test.mp4",
          collection: "markpines",
          files_json: "[]"
        })

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "classification_status accepts valid enum values" do
      for status <- [:pending, :queued, :classifying, :classified, :failed] do
        changeset =
          Video.changeset(%Video{}, %{
            archive_id: "test_#{status}",
            title: "Test",
            primary_video_url: "https://example.com/test.mp4",
            collection: "markpines",
            files_json: "[]",
            classification_status: status
          })

        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "defaults to pending status" do
      changeset =
        Video.changeset(%Video{}, %{
          archive_id: "test",
          title: "Test",
          primary_video_url: "https://example.com/test.mp4",
          collection: "markpines",
          files_json: "[]"
        })

      assert Ecto.Changeset.get_field(changeset, :classification_status) == :pending
    end

    test "tags default to empty list" do
      changeset =
        Video.changeset(%Video{}, %{
          archive_id: "test",
          title: "Test",
          primary_video_url: "https://example.com/test.mp4",
          collection: "markpines",
          files_json: "[]"
        })

      assert Ecto.Changeset.get_field(changeset, :tags) == []
    end
  end
end
