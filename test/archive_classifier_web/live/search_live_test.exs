defmodule ArchiveClassifierWeb.SearchLiveTest do
  use ArchiveClassifierWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Classification.Transcript
  alias ArchiveClassifier.Repo

  setup do
    video =
      Repo.insert!(%Video{
        archive_id: "test-video-001",
        title: "Ron Wood Rehearsal 1982",
        primary_video_url: "https://archive.org/download/test/test.mp4",
        collection: "markpines",
        files_json: "[]"
      })

    Repo.insert!(%Transcript{
      video_id: video.id,
      start_time: 12.5,
      end_time: 18.3,
      text: "dancing in the moonlight"
    })

    Repo.insert!(%Transcript{
      video_id: video.id,
      start_time: 45.0,
      end_time: 52.0,
      text: "guitar solo with Keith Richards"
    })

    %{video: video}
  end

  describe "URL-driven search" do
    test "landing page with no query param shows empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search")

      assert html =~ "Type to search across all transcribed videos"
      refute html =~ "matches"
    end

    test "visiting with ?q= param shows search results", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=dancing")

      assert html =~ "dancing in the moonlight"
      assert html =~ "Ron Wood Rehearsal 1982"
    end

    test "visiting with ?q= param that matches nothing shows no-results message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=zzzznotfound")

      assert html =~ "No transcript matches found"
    end

    test "typing in search input patches the URL with ?q=", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/search")

      view
      |> form("form", %{q: "dancing"})
      |> render_change()

      assert_patch(view, ~p"/search?q=dancing")
    end

    test "search results update when URL query param changes via patch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/search")

      html =
        view
        |> form("form", %{q: "guitar"})
        |> render_change()

      assert html =~ "guitar solo with Keith Richards"
      refute html =~ "dancing in the moonlight"
    end

    test "short queries (less than 2 chars) return no results", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=d")

      refute html =~ "dancing in the moonlight"
    end

    test "empty q param behaves like no query", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/search?q=")

      assert html =~ "Type to search across all transcribed videos"
    end
  end
end
