defmodule ArchiveClassifier.Repo do
  use Ecto.Repo,
    otp_app: :archive_classifier,
    adapter: Ecto.Adapters.Postgres
end
