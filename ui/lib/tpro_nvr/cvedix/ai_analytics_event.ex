defmodule TProNVR.CVEDIX.AIAnalyticsEvent do
  @moduledoc """
  Schema for storing analytics events from CVEDIX-RT.
  Supports multiple event types:
  - event-intrusion: Object enters intrusion area
  - event-intrusion-end: Object leaves intrusion area
  - event-area-enter: Object enters detection area
  - event-area-exit: Object exits detection area
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @event_types [
    "event-intrusion",
    "event-intrusion-end",
    "event-area-enter",
    "event-area-exit",
    "event-loitering",
    "event-loitering-end",
    "event-line-crossing",
    "event-crowd",
    "event-activity",
    "event-activity-end",
    "event-dwelling"
  ]

  @derive {Flop.Schema,
           filterable: [
             :event_type,
             :area_id,
             :area_name,
             :object_class,
             :ref_tracking_id,
             :device_id,
             :instance_id,
             :inserted_at
           ],
           sortable: [:inserted_at, :system_datetime, :event_type, :area_name, :object_class],
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
  schema "ai_analytics_events" do
    field :instance_id, :string
    field :event_type, :string
    field :event_id, :string
    field :ref_tracking_id, :string
    field :ref_event_id, :string
    
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

  @required_fields [:instance_id, :event_type]
  @optional_fields [
    :device_id, :event_id, :ref_tracking_id, :ref_event_id, :area_id, :area_name,
    :object_class, :event_timestamp_ms, :location_x, :location_y,
    :location_width, :location_height, :system_datetime,
    :system_timestamp, :raw_data
  ]

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
    |> Changeset.validate_inclusion(:event_type, @event_types)
  end

  def event_types, do: @event_types

  @doc """
  Get the latest events for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 50) do
    from(e in __MODULE__,
      where: e.instance_id == ^instance_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get events by type.
  """
  def by_type(event_type) do
    from(e in __MODULE__,
      where: e.event_type == ^event_type,
      order_by: [desc: e.inserted_at]
    )
  end

  @doc """
  Get events for a specific area.
  """
  def by_area(area_id) do
    from(e in __MODULE__,
      where: e.area_id == ^area_id,
      order_by: [desc: e.inserted_at]
    )
  end
end
