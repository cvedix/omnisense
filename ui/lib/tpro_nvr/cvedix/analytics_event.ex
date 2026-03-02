defmodule TProNVR.CVEDIX.AnalyticsEvent do
  @moduledoc """
  Schema for storing AI Analytics events from CVEDIX-RT.
  Supports filtering by event_type, object_class, zone_name, date range, etc.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :event_type,
             :event_subtype,
             :object_class,
             :zone_name,
             :direction,
             :device_id,
             :instance_id,
             :event_time
           ],
           sortable: [:event_time, :event_type, :object_class, :confidence],
           default_order: %{
             order_by: [:event_time],
             order_directions: [:desc]
           },
           adapter_opts: [
             join_fields: [
               device_name: [
                 binding: :device,
                 field: :name,
                 ecto_type: :string
               ]
             ]
           ],
           pagination_types: [:page],
           default_limit: 50,
           max_limit: 100}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:device, :__meta__]}
  schema "analytics_events" do
    field :instance_id, :string
    field :event_type, :string
    field :event_subtype, :string
    field :zone_name, :string
    field :zone_id, :string
    field :object_class, :string
    field :object_id, :integer
    field :confidence, :float
    field :direction, :string
    field :bounding_box, :map
    field :centroid_x, :float
    field :centroid_y, :float
    field :track_path, {:array, :map}, default: []
    field :frame_width, :integer
    field :frame_height, :integer
    field :attributes, :map, default: %{}
    field :thumbnail_path, :string
    field :event_time, :utc_datetime_usec
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id, :event_type, :event_time]
  @optional_fields [
    :device_id, :event_subtype, :zone_name, :zone_id, :object_class,
    :object_id, :confidence, :direction, :bounding_box, :centroid_x,
    :centroid_y, :track_path, :frame_width, :frame_height, :attributes,
    :thumbnail_path, :raw_data
  ]

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
    |> Changeset.validate_inclusion(:event_type, [
      "intrusion", "loitering", "crowding", "crossing", 
      "tailgating", "line_counting", "motion", "object_detection",
      "face_detection", "fire_detection", "lpd_detection",
      "track", "crop", "attribute", "statistics",
      "area_enter", "area_exit", "count_changed", "dwelling"
    ])
  end

  @doc """
  Filter query by common parameters.
  """
  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {"start_date", start_date}, q -> where(q, [e], e.event_time >= ^start_date)
      {"end_date", end_date}, q -> where(q, [e], e.event_time <= ^end_date)
      {"event_type", event_type}, q -> where(q, [e], e.event_type == ^event_type)
      {"object_class", object_class}, q -> where(q, [e], e.object_class == ^object_class)
      {"zone_name", zone_name}, q -> where(q, [e], e.zone_name == ^zone_name)
      {"device_id", device_id}, q -> where(q, [e], e.device_id == ^device_id)
      {"instance_id", instance_id}, q -> where(q, [e], e.instance_id == ^instance_id)
      _, q -> q
    end)
  end

  @doc """
  Get events grouped by event_type for statistics.
  """
  def count_by_type(query \\ __MODULE__) do
    query
    |> group_by([e], e.event_type)
    |> select([e], {e.event_type, count(e.id)})
  end

  @doc """
  Get events grouped by object_class for statistics.
  """
  def count_by_object_class(query \\ __MODULE__) do
    query
    |> group_by([e], e.object_class)
    |> select([e], {e.object_class, count(e.id)})
  end
end
