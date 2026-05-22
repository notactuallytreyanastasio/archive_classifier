defmodule ArchiveClassifierWeb.Router do
  use ArchiveClassifierWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArchiveClassifierWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArchiveClassifierWeb do
    pipe_through :browser

    live "/", CatalogLive
    live "/search", SearchLive

    live "/videos/:id/transcript", TranscriptSearchLive

    get "/thumbnails/:id", ThumbnailController, :show
    get "/frames/:id", FrameController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", ArchiveClassifierWeb do
  #   pipe_through :api
  # end
end
