defmodule TProNVR.CVEDIX.Attribute do
  @moduledoc """
  Schema for storing attribute detection events from CVEDIX-RT.
  Attributes describe characteristics of detected objects such as:
  - age, gender, glasses
  - upper_clothing_color, carrying_bag
  - tattoo, phone, smoking, etc.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :name,
             :value,
             :ref_tracking_id,
             :device_id,
             :instance_id,
             :inserted_at
           ],
           sortable: [:inserted_at, :system_datetime, :name],
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
  schema "ai_analytics_attributes" do
    field :instance_id, :string
    field :name, :string
    field :value, :string
    field :ref_tracking_id, :string
    
    # Timestamps from source
    field :event_timestamp_ms, :integer
    field :system_datetime, :utc_datetime_usec
    field :system_timestamp, :integer
    
    # Raw JSON
    field :raw_data, :map, default: %{}

    belongs_to(:device, TProNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:instance_id, :name]
  @optional_fields [
    :device_id, :value, :ref_tracking_id, :event_timestamp_ms,
    :system_datetime, :system_timestamp, :raw_data
  ]

  def changeset(attribute \\ %__MODULE__{}, params) do
    attribute
    |> Changeset.cast(params, @required_fields ++ @optional_fields)
    |> Changeset.validate_required(@required_fields)
  end

  @doc """
  Get the latest attributes for an instance.
  """
  def latest_by_instance(instance_id, limit \\ 50) do
    from(a in __MODULE__,
      where: a.instance_id == ^instance_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Get attributes for a specific tracking ID.
  """
  def by_tracking_id(tracking_id) do
    from(a in __MODULE__,
      where: a.ref_tracking_id == ^tracking_id,
      order_by: [desc: a.inserted_at]
    )
  end

  @doc """
  Get attributes by name.
  """
  def by_name(name) do
    from(a in __MODULE__,
      where: a.name == ^name,
      order_by: [desc: a.inserted_at]
    )
  end
end
