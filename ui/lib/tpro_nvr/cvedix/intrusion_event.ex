defmodule TProNVR.CVEDIX.IntrusionEvent do
  @moduledoc """
  Schema for storing intrusion detection events from CVEDIX-RT.
  Each intrusion event represents an object entering a defined intrusion area.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :area_id,
             :area_name,
             :object_class,
             :ref_tracking_id,
             :device_id,
             :instance_id,
             :inserted_at
           ],
           sortable: [:inserted_at, :system_datetime, :area_name, :object_class],
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
  schema "ai_analytics_intrusions" do
    field :instance_id, :string
    field :event_id, :string
    field :ref_tracking_id, :string
    
    # Area info
    field :area_id, :string
    field :area_name, :string
    
    # Detection data
    field :object_class, :string
    field :event_timestamp_ms, :integer
    
    # Location (bounding box normalized 0-1)
    field :location_x, :float
    field :location_y, :float
    field :location_width, :float
    field :location_height, :float
    
    # Timestamps from source
    field :system_datetime, :utc_datetime_usec
    field :system_timestamp, :integer
    
    # Raw JSON
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id]
  @optional_fields [
    :device_id, :event_id, :ref_tracking_id, :area_id, :area_name,
    :object_class, :event_timestamp_ms, :location_x, :location_y,
    :location_width, :location_height, :system_datetime,
    :system_timestamp, :raw_data
  ]

  def changeset(intrusion \\ %__MODULE__{}, params) do
    intrusion
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
  end

  @doc """
  Get the latest intrusions for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 50) do
    from(i in __MODULE__,
      where: i.instance_id == ^instance_id,
      order_by: [desc: i.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get intrusions for a specific area.
  """
  def by_area(area_id) do
    from(i in __MODULE__,
      where: i.area_id == ^area_id,
      order_by: [desc: i.inserted_at]
    )
  end
end
