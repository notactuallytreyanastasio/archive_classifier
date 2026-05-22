defmodule ArchiveClassifierWeb.ThumbnailController do
  @moduledoc """
  Serves cached thumbnail images from ETS.
  Falls back to a redirect to archive.org if not cached.
  """

  use ArchiveClassifierWeb, :controller

  alias ArchiveClassifier.Cache

  def show(conn, %{"id" => id}) do
    case Cache.get(String.to_integer(id)) do
      %{thumbnail: thumbnail} when is_binary(thumbnail) and byte_size(thumbnail) > 0 ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, thumbnail)

      %{archive_id: archive_id} ->
        redirect(conn, external: "https://archive.org/services/img/#{archive_id}")

      nil ->
        send_resp(conn, 404, "")
    end
  end
end
