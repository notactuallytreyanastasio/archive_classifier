defmodule ArchiveClassifierWeb.PageController do
  use ArchiveClassifierWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
