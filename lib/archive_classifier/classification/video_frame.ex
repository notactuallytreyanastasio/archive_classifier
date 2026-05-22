defmodule ArchiveClassifier.Classification.VideoFrame do
  @moduledoc """
  A single extracted frame from a video at a specific timestamp.
  Stored as a JPEG binary blob.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchiveClassifier.Archive.Video

  @type t :: %__MODULE__{
          id: integer() | nil,
          video_id: integer(),
          timestamp: float(),
          image: binary()
        }

  schema "video_frames" do
    belongs_to :video, Video
    field :timestamp, :float
    field :image, :binary

    timestamps()
  end

  @required_fields ~w(video_id timestamp image)a

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(frame, attrs) do
    frame
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:video_id)
  end
end
