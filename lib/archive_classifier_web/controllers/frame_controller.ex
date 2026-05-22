defmodule ArchiveClassifierWeb.FrameController do
  @moduledoc """
  Serves extracted video frames by ID.
  """

  use ArchiveClassifierWeb, :controller

  alias ArchiveClassifier.Classification.VideoFrame
  alias ArchiveClassifier.Repo

  def show(conn, %{"id" => id}) do
    case Repo.get(VideoFrame, id) do
      %VideoFrame{image: image} when is_binary(image) ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> put_resp_header("cache-control", "public, max-age=604800")
        |> send_resp(200, image)

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
