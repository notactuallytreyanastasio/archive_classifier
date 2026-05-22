defmodule ArchiveClassifier.CacheTest do
  use ArchiveClassifier.DataCase, async: false

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Cache

  defp insert_video!(attrs \\ %{}) do
    defaults = %{
      archive_id: "cache_test_#{System.unique_integer([:positive])}",
      title: "Cache Test Video",
      primary_video_url: "https://archive.org/download/test/test.mp4",
      collection: "markpines",
      files_json: "[]"
    }

    %Video{}
    |> Video.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "all_videos/0" do
    test "returns videos from cache" do
      insert_video!(%{title: "Cached Video"})
      Cache.reload_all()

      videos = Cache.all_videos()
      assert Enum.any?(videos, &(&1.title == "Cached Video"))
    end
  end

  describe "search/1" do
    test "returns all videos for empty search" do
      insert_video!(%{title: "Something"})
      Cache.reload_all()

      assert length(Cache.search("")) > 0
      assert length(Cache.search(nil)) > 0
    end

    test "filters by title" do
      insert_video!(%{title: "Unique Cache Search Term XYZ"})
      Cache.reload_all()

      results = Cache.search("Unique Cache Search Term XYZ")
      assert length(results) == 1
    end

    test "filters by description" do
      insert_video!(%{title: "Generic", description: "very specific description zqx"})
      Cache.reload_all()

      results = Cache.search("zqx")
      assert length(results) == 1
    end

    test "case-insensitive" do
      insert_video!(%{title: "UPPERCASE TITLE"})
      Cache.reload_all()

      assert length(Cache.search("uppercase")) >= 1
    end
  end

  describe "get/1" do
    test "returns video by id" do
      video = insert_video!()
      Cache.reload_all()

      assert Cache.get(video.id).id == video.id
    end

    test "returns nil for missing id" do
      assert Cache.get(-999) == nil
    end
  end

  describe "stats/0" do
    test "returns counts by status" do
      insert_video!(%{classification_status: :pending})
      insert_video!(%{classification_status: :classified})
      Cache.reload_all()

      stats = Cache.stats()
      assert stats.total >= 2
      assert stats.pending >= 1
      assert stats.classified >= 1
    end
  end

  describe "reload/1" do
    test "updates a single video in cache" do
      video = insert_video!(%{classification_status: :pending})
      Cache.reload_all()

      # Update in DB
      video
      |> Video.changeset(%{classification_status: :classified})
      |> Repo.update!()

      # Cache still has old value
      assert Cache.get(video.id).classification_status == :pending

      # Reload
      Cache.reload(video.id)

      # Now cache has new value
      assert Cache.get(video.id).classification_status == :classified
    end
  end
end
