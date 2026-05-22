defmodule ArchiveClassifier.Classification.Transcript do
  @moduledoc """
  A timestamped transcript segment for a video.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchiveClassifier.Archive.Video

  @type t :: %__MODULE__{
          id: integer() | nil,
          video_id: integer(),
          start_time: float(),
          end_time: float(),
          text: String.t()
        }

  schema "transcripts" do
    belongs_to :video, Video
    field :start_time, :float
    field :end_time, :float
    field :text, :string

    timestamps()
  end

  @required_fields ~w(video_id start_time end_time text)a

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:video_id)
  end
end
