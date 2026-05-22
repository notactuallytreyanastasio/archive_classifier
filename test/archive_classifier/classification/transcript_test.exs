defmodule ArchiveClassifier.Classification.TranscriptTest do
  use ArchiveClassifier.DataCase, async: true

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Classification.Transcript

  defp insert_video!(attrs \\ %{}) do
    defaults = %{
      archive_id: "test_#{System.unique_integer([:positive])}",
      title: "Test Video",
      primary_video_url: "https://archive.org/download/test/test.mp4",
      collection: "markpines",
      files_json: "[]"
    }

    %Video{}
    |> Video.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_transcript!(video, attrs) do
    defaults = %{
      video_id: video.id,
      start_time: 0.0,
      end_time: 30.0,
      text: "some spoken words"
    }

    %Transcript{}
    |> Transcript.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "changeset/2" do
    test "valid with all required fields" do
      video = insert_video!()

      changeset =
        Transcript.changeset(%Transcript{}, %{
          video_id: video.id,
          start_time: 10.5,
          end_time: 25.0,
          text: "hello world"
        })

      assert changeset.valid?
    end

    test "invalid without text" do
      video = insert_video!()

      changeset =
        Transcript.changeset(%Transcript{}, %{
          video_id: video.id,
          start_time: 0.0,
          end_time: 10.0
        })

      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without timestamps" do
      video = insert_video!()

      changeset =
        Transcript.changeset(%Transcript{}, %{
          video_id: video.id,
          text: "hello"
        })

      refute changeset.valid?
      assert %{start_time: ["can't be blank"], end_time: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "search via Ecto query" do
    test "ilike search finds matching transcript segments" do
      import Ecto.Query

      video = insert_video!(%{title: "Ron Wood Interview"})
      insert_transcript!(video, %{text: "and then Ronnie picked up the guitar", start_time: 45.0, end_time: 60.0})
      insert_transcript!(video, %{text: "the crowd was going wild", start_time: 60.0, end_time: 75.0})

      video2 = insert_video!(%{title: "Jazz Show"})
      insert_transcript!(video2, %{text: "beautiful guitar solo here", start_time: 120.0, end_time: 150.0})

      results =
        from(t in Transcript,
          join: v in Video,
          on: t.video_id == v.id,
          where: ilike(t.text, ^"%guitar%"),
          select: %{text: t.text, start_time: t.start_time, title: v.title}
        )
        |> Repo.all()

      assert length(results) == 2
      assert Enum.any?(results, &(&1.start_time == 45.0))
      assert Enum.any?(results, &(&1.start_time == 120.0))
    end

    test "search is case-insensitive" do
      import Ecto.Query

      video = insert_video!()
      insert_transcript!(video, %{text: "Ronnie Wood plays guitar"})

      results =
        from(t in Transcript, where: ilike(t.text, ^"%ronnie wood%"))
        |> Repo.all()

      assert length(results) == 1
    end
  end
end
