defmodule ArchiveClassifier.Archive.Video do
  @moduledoc """
  An archive video from the markpines collection.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          duration: float() | nil,
          primary_video_url: String.t(),
          collection: String.t(),
          files_json: String.t(),
          classification_status: String.t(),
          tags: [String.t()]
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "videos" do
    field :title, :string
    field :description, :string
    field :duration, :float
    field :primary_video_url, :string
    field :collection, :string
    field :files_json, :string
    field :classification_status, :string, default: "pending"
    field :tags, {:array, :string}, default: []

    timestamps()
  end

  @required_fields ~w(id title primary_video_url collection files_json)a
  @optional_fields ~w(description duration classification_status tags)a

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(video, attrs) do
    video
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
