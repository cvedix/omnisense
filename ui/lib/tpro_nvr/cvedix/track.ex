defmodule TProNVR.CVEDIX.Track do
  @moduledoc """
  Schema for storing object tracking data from CVEDIX-RT.
  Each track represents a detected object's position and movement over time.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :tracking_id,
             :object_class,
             :device_id,
             :instance_id,
             :is_moving,
             :inserted_at
           ],
           sortable: [:inserted_at, :system_datetime, :object_class, :detection_confidence],
           default_order: %{
             order_by: [:inserted_at],
             order_directions: [:desc]
           },
           pagination_types: [:page],
           default_limit: 100,
           max_limit: 500}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:device, :__meta__]}
  schema "ai_analytics_tracks" do
    field :instance_id, :string
    field :tracking_id, :string
    field :object_class, :string
    
    # Detection data
    field :detection_confidence, :float
    field :age_ms, :integer
    field :is_moving, :integer
    field :event_timestamp_ms, :integer
    
    # Location (bounding box normalized 0-1)
    field :location_x, :float
    field :location_y, :float
    field :location_width, :float
    field :location_height, :float
    
    # Centroid
    field :centroid_x, :float
    field :centroid_y, :float
    
    # Related events
    field :events, {:array, :string}, default: []
    
    # Timestamps from source
    field :system_datetime, :utc_datetime_usec
    field :system_timestamp, :integer
    
    # Raw JSON
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id, :tracking_id]
  @optional_fields [
    :device_id, :object_class, :detection_confidence, :age_ms, :is_moving,
    :event_timestamp_ms, :location_x, :location_y, :location_width, :location_height,
    :centroid_x, :centroid_y, :events, :system_datetime, :system_timestamp, :raw_data
  ]

  def changeset(track \\ %__MODULE__{}, params) do
    track
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
  end

  @doc """
  Filter query by common parameters.
  """
  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {"device_id", device_id}, q -> where(q, [t], t.device_id == ^device_id)
      {"instance_id", instance_id}, q -> where(q, [t], t.instance_id == ^instance_id)
      {"tracking_id", tracking_id}, q -> where(q, [t], t.tracking_id == ^tracking_id)
      {"object_class", object_class}, q -> where(q, [t], t.object_class == ^object_class)
      {"is_moving", is_moving}, q -> where(q, [t], t.is_moving == ^is_moving)
      {"start_date", start_date}, q -> where(q, [t], t.inserted_at >= ^start_date)
      {"end_date", end_date}, q -> where(q, [t], t.inserted_at <= ^end_date)
      _, q -> q
    end)
  end

  @doc """
  Get the latest tracks for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 100) do
    from(t in __MODULE__,
      where: t.instance_id == ^instance_id,
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get unique tracking IDs currently active (recent tracks).
  """
  def active_tracks(instance_id, since_seconds \\ 5) do
    since = DateTime.add(DateTime.utc_now(), -since_seconds, :second)
    
    from(t in __MODULE__,
      where: t.instance_id == ^instance_id and t.inserted_at >= ^since,
      distinct: t.tracking_id,
      order_by: [desc: t.inserted_at],
      select: %{
        tracking_id: t.tracking_id,
        object_class: t.object_class,
        location_x: t.location_x,
        location_y: t.location_y,
        location_width: t.location_width,
        location_height: t.location_height,
        is_moving: t.is_moving
      }
    )
  end
end
