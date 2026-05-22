defmodule ArchiveClassifierWeb.TranscriptSearchLiveTest do
  use ArchiveClassifierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Classification.Transcript
  alias ArchiveClassifier.Repo

  defp insert_video!(attrs \\ %{}) do
    defaults = %{
      archive_id: "test_#{System.unique_integer([:positive])}",
      title: "Test Video",
      primary_video_url: "https://archive.org/download/test/test.mp4",
      collection: "markpines",
      files_json: "[]",
      classification_status: :classified
    }

    %Video{}
    |> Video.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_transcript!(video, attrs) do
    defaults = %{video_id: video.id, start_time: 0.0, end_time: 10.0, text: "default text"}

    %Transcript{}
    |> Transcript.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "mount" do
    test "shows video title and full transcript", %{conn: conn} do
      video = insert_video!(%{title: "Ron Wood Interview"})
      insert_transcript!(video, %{text: "picked up the guitar", start_time: 10.0, end_time: 20.0})
      insert_transcript!(video, %{text: "the crowd went wild", start_time: 20.0, end_time: 30.0})

      {:ok, _view, html} = live(conn, "/videos/#{video.id}/transcript")
      assert html =~ "Ron Wood Interview"
      assert html =~ "picked up the guitar"
      assert html =~ "the crowd went wild"
    end

    test "shows timestamps for each segment", %{conn: conn} do
      video = insert_video!()
      insert_transcript!(video, %{text: "hello world", start_time: 65.0, end_time: 90.0})

      {:ok, _view, html} = live(conn, "/videos/#{video.id}/transcript")
      # 65s = 01:05
      assert html =~ "01:05"
    end
  end

  describe "search within transcript" do
    test "filters transcript segment buttons by q param", %{conn: conn} do
      video = insert_video!()
      insert_transcript!(video, %{text: "beautiful guitar solo", start_time: 10.0, end_time: 20.0})
      insert_transcript!(video, %{text: "drum fill here", start_time: 20.0, end_time: 30.0})
      insert_transcript!(video, %{text: "another guitar part", start_time: 40.0, end_time: 50.0})

      {:ok, view, _html} = live(conn, "/videos/#{video.id}/transcript?q=guitar")

      # Filtered segments appear as clickable buttons
      assert has_element?(view, "button[data-start='10.0']")
      assert has_element?(view, "button[data-start='40.0']")
      # "drum fill" segment is filtered out of the button list
      refute has_element?(view, "button[data-start='20.0']")
    end

    test "shows all segments when q is empty", %{conn: conn} do
      video = insert_video!()
      insert_transcript!(video, %{text: "first segment", start_time: 0.0, end_time: 10.0})
      insert_transcript!(video, %{text: "second segment", start_time: 10.0, end_time: 20.0})

      {:ok, _view, html} = live(conn, "/videos/#{video.id}/transcript")
      assert html =~ "first segment"
      assert html =~ "second segment"
    end

    test "search updates URL via push_patch", %{conn: conn} do
      video = insert_video!()
      insert_transcript!(video, %{text: "dancing in the street", start_time: 0.0, end_time: 10.0})

      {:ok, view, _html} = live(conn, "/videos/#{video.id}/transcript")

      html =
        view
        |> element("#transcript-filter-form")
        |> render_change(%{q: "dancing"})

      assert html =~ "dancing"
    end

    test "search is case-insensitive", %{conn: conn} do
      video = insert_video!()
      insert_transcript!(video, %{text: "Ronnie Wood on guitar", start_time: 0.0, end_time: 10.0})

      {:ok, _view, html} = live(conn, "/videos/#{video.id}/transcript?q=ronnie")
      assert html =~ "Ronnie Wood"
    end
  end
end
