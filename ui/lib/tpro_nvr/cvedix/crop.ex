defmodule TProNVR.CVEDIX.Crop do
  @moduledoc """
  Schema for storing cropped images from CVEDIX-RT object detection.
  Each crop represents an image crop of a detected object.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :ref_tracking_id,
             :device_id,
             :instance_id,
             :inserted_at
           ],
           sortable: [:inserted_at, :system_datetime, :confidence],
           default_order: %{
             order_by: [:inserted_at],
             order_directions: [:desc]
           },
           pagination_types: [:page],
           default_limit: 50,
           max_limit: 200}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:device, :__meta__]}
  schema "ai_analytics_crops" do
    field :instance_id, :string
    field :ref_tracking_id, :string
    field :ref_event_id, :string
    
    # Detection data
    field :confidence, :float
    field :crop_timestamp_ms, :integer
    field :event_timestamp_ms, :integer
    
    # Location (bounding box normalized 0-1)
    field :location_x, :float
    field :location_y, :float
    field :location_width, :float
    field :location_height, :float
    
    # Image storage
    field :image_path, :string
    field :base64_image, :string
    
    # Timestamps from source
    field :system_datetime, :utc_datetime_usec
    field :system_timestamp, :integer
    
    # Raw JSON (without image)
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id]
  @optional_fields [
    :device_id, :ref_tracking_id, :ref_event_id, :confidence,
    :crop_timestamp_ms, :event_timestamp_ms, :location_x, :location_y,
    :location_width, :location_height, :image_path, :base64_image, :system_datetime,
    :system_timestamp, :raw_data
  ]

  def changeset(crop \\ %__MODULE__{}, params) do
    crop
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
  end

  @doc """
  Get the latest crops for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 50) do
    from(c in __MODULE__,
      where: c.instance_id == ^instance_id,
      order_by: [desc: c.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get crops for a specific tracking ID.
  """
  def by_tracking_id(tracking_id) do
    from(c in __MODULE__,
      where: c.ref_tracking_id == ^tracking_id,
      order_by: [desc: c.inserted_at]
    )
  end
end
