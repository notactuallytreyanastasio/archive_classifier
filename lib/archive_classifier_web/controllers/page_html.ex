defmodule ArchiveClassifierWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use ArchiveClassifierWeb, :html

  embed_templates "page_html/*"
end
