defmodule ArchiveClassifier.ArchiveTest do
  use ArchiveClassifier.DataCase, async: true

  alias ArchiveClassifier.Archive
  alias ArchiveClassifier.Archive.Video

  defp insert_video!(attrs \\ %{}) do
    defaults = %{
      archive_id: "test_video_#{System.unique_integer([:positive])}",
      title: "Test Video",
      description: "A test video description",
      duration: 120.0,
      primary_video_url: "https://archive.org/download/test/test.mp4",
      collection: "markpines",
      files_json: "[]",
      classification_status: :pending,
      tags: []
    }

    %Video{}
    |> Video.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "list_videos/1" do
    test "returns videos ordered by duration ascending" do
      long = insert_video!(%{title: "Long one", duration: 3600.0})
      short = insert_video!(%{title: "Short one", duration: 30.0})
      mid = insert_video!(%{title: "Mid one", duration: 600.0})

      result = Archive.list_videos()
      ids = Enum.map(result, & &1.id)

      assert ids == [short.id, mid.id, long.id]
    end

    test "filters by search term across title and description" do
      insert_video!(%{title: "Ron Wood Interview", description: "Backstage at the Ritz"})
      insert_video!(%{title: "Jazz at the Smithsonian", description: "Various artists"})
      insert_video!(%{title: "Rehearsal tape", description: "Ron Wood on guitar"})

      result = Archive.list_videos(search: "Ron Wood")
      assert length(result) == 2

      result = Archive.list_videos(search: "smithsonian")
      assert length(result) == 1
    end

    test "search is case-insensitive" do
      insert_video!(%{title: "Queen Live at Milton Keynes"})

      assert length(Archive.list_videos(search: "queen")) == 1
      assert length(Archive.list_videos(search: "QUEEN")) == 1
    end

    test "filters by classification status" do
      insert_video!(%{classification_status: :pending})
      insert_video!(%{classification_status: :queued})
      insert_video!(%{classification_status: :classified})

      assert length(Archive.list_videos(status: :pending)) == 1
      assert length(Archive.list_videos(status: :queued)) == 1
    end

    test "respects limit" do
      for _ <- 1..5, do: insert_video!()

      assert length(Archive.list_videos(limit: 3)) == 3
    end
  end

  describe "count_videos/1" do
    test "returns total count" do
      for _ <- 1..3, do: insert_video!()

      assert Archive.count_videos() == 3
    end

    test "counts with search filter" do
      insert_video!(%{title: "Ron Wood Interview"})
      insert_video!(%{title: "Jazz Greats"})

      assert Archive.count_videos(search: "Ron Wood") == 1
    end
  end

  describe "get_video!/1" do
    test "returns video by id" do
      video = insert_video!()

      assert Archive.get_video!(video.id).id == video.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Archive.get_video!(-1)
      end
    end
  end

  describe "queue_for_classification/1" do
    test "sets status to queued" do
      video = insert_video!(%{classification_status: :pending})

      assert {:ok, updated} = Archive.queue_for_classification(video)
      assert updated.classification_status == :queued
    end
  end

  describe "stats/0" do
    test "returns counts by status" do
      insert_video!(%{classification_status: :pending})
      insert_video!(%{classification_status: :pending})
      insert_video!(%{classification_status: :queued})
      insert_video!(%{classification_status: :classified})

      stats = Archive.stats()

      assert stats.total == 4
      assert stats.pending == 2
      assert stats.queued == 1
      assert stats.classified == 1
    end
  end
end
