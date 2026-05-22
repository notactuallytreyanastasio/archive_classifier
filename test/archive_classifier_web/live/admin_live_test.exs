defmodule ArchiveClassifierWeb.AdminLiveTest do
  use ArchiveClassifierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ArchiveClassifier.Archive.Video
  alias ArchiveClassifier.Repo

  defp insert_video!(attrs) do
    defaults = %{
      archive_id: "admin_test_#{System.unique_integer([:positive])}",
      title: "Admin Test Video",
      primary_video_url: "https://archive.org/download/test/test.mp4",
      collection: "markpines",
      files_json: "[]",
      classification_status: :pending
    }

    %Video{}
    |> Video.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "mount" do
    test "renders admin page with filter inputs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")
      assert html =~ "Admin"
      assert html =~ "min_duration"
      assert html =~ "max_duration"
      assert html =~ "collection"
    end
  end

  describe "filtering" do
    test "filters by duration range", %{conn: conn} do
      insert_video!(%{title: "Short", duration: 60.0})
      insert_video!(%{title: "Medium", duration: 300.0})
      insert_video!(%{title: "Long", duration: 3600.0})

      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> element("#admin-filters")
        |> render_change(%{filters: %{min_duration: "2:00", max_duration: "10:00"}})

      assert html =~ "Medium"
      refute html =~ "Short"
      refute html =~ "Long"
    end

    test "filters by collection", %{conn: conn} do
      insert_video!(%{title: "Pines Vid", collection: "markpines"})
      insert_video!(%{title: "Ron Vid", collection: "mp_ronwood"})

      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> element("#admin-filters")
        |> render_change(%{filters: %{collection: "mp_ronwood"}})

      assert html =~ "Ron Vid"
      refute html =~ "Pines Vid"
    end

    test "filters by search term", %{conn: conn} do
      insert_video!(%{title: "Magic Johnson Interview"})
      insert_video!(%{title: "Jazz at the Smithsonian"})

      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> element("#admin-filters")
        |> render_change(%{filters: %{search: "Magic Johnson"}})

      assert html =~ "Magic Johnson"
      refute html =~ "Smithsonian"
    end

    test "shows match count", %{conn: conn} do
      for i <- 1..5, do: insert_video!(%{title: "Batch #{i}", duration: 300.0})

      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> element("#admin-filters")
        |> render_change(%{filters: %{min_duration: "4:00", max_duration: "6:00"}})

      assert html =~ "5 videos match"
    end
  end

  describe "enqueue" do
    test "enqueue all creates twerker jobs and sets status to queued", %{conn: conn} do
      v1 = insert_video!(%{title: "Enqueue Me 1", duration: 300.0})
      v2 = insert_video!(%{title: "Enqueue Me 2", duration: 300.0})

      {:ok, view, _html} = live(conn, "/admin")

      # Filter to our test videos
      view
      |> element("#admin-filters")
      |> render_change(%{filters: %{search: "Enqueue Me", min_duration: "4:00", max_duration: "6:00"}})

      # Click enqueue all
      view
      |> element("#enqueue-all-btn")
      |> render_click()

      # Videos should be queued
      assert Repo.get!(Video, v1.id).classification_status == :queued
      assert Repo.get!(Video, v2.id).classification_status == :queued
    end
  end
end
