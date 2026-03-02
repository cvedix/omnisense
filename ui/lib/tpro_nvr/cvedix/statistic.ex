defmodule TProNVR.CVEDIX.Statistic do
  @moduledoc """
  Schema for storing AI Analytics statistics/performance metrics from CVEDIX-RT.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [:device_id, :instance_id, :inserted_at],
           sortable: [:inserted_at, :current_framerate, :latency],
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
  schema "ai_analytics_statistics" do
    field :instance_id, :string
    
    # Performance metrics
    field :current_framerate, :float
    field :source_framerate, :float
    field :dropped_frames_count, :integer
    field :frames_processed, :integer
    field :input_queue_size, :integer
    field :latency, :float
    
    # Format info
    field :format, :string
    field :resolution, :string
    field :source_resolution, :string
    
    # Timing
    field :start_time, :integer
    
    # Raw data
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id]
  @optional_fields [
    :device_id, :current_framerate, :source_framerate, :dropped_frames_count,
    :frames_processed, :input_queue_size, :latency, :format, :resolution,
    :source_resolution, :start_time, :raw_data
  ]

  def changeset(stat \\ %__MODULE__{}, params) do
    stat
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
  end

  @doc """
  Get the latest statistics for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 10) do
    from(s in __MODULE__,
      where: s.instance_id == ^instance_id,
      order_by: [desc: s.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get average metrics over a time period.
  """
  def average_metrics(instance_id, since_minutes \\ 5) do
    since = DateTime.add(DateTime.utc_now(), -since_minutes, :minute)
    
    from(s in __MODULE__,
      where: s.instance_id == ^instance_id and s.inserted_at >= ^since,
      select: %{
        avg_framerate: avg(s.current_framerate),
        avg_latency: avg(s.latency),
        total_dropped: sum(s.dropped_frames_count),
        total_processed: sum(s.frames_processed)
      }
    )
  end
end
