defmodule TProNVR.Repo.Migrations.CreateAnalyticsEvents do
  use Ecto.Migration

  def change do
    create table("analytics_events", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instance_id, :string, null: false
      add :device_id, references("devices", type: :binary_id, on_delete: :delete_all)
      
      # Event classification
      add :event_type, :string, null: false  # intrusion, loitering, crowding, crossing, tailgating, line_counting
      add :event_subtype, :string  # More specific type
      
      # Zone/Line info
      add :zone_name, :string
      add :zone_id, :string
      
      # Object info
      add :object_class, :string  # Person, Vehicle, Animal, Face, LPD, Fire
      add :object_id, :integer  # Track ID
      add :confidence, :float
      add :direction, :string  # Up, Down, Left, Right
      
      # Spatial data
      add :bounding_box, :map  # {x, y, w, h}
      
      # Extracted attributes
      add :attributes, :map, default: %{}  # age, gender, clothes, vehicle_color, etc.
      
      # Media
      add :thumbnail_path, :string
      
      # Timing
      add :event_time, :utc_datetime_usec, null: false
      
      # Raw data for debugging
      add :raw_data, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Indexes for common queries
    create index("analytics_events", [:device_id])
    create index("analytics_events", [:instance_id])
    create index("analytics_events", [:event_type])
    create index("analytics_events", [:event_time])
    create index("analytics_events", [:object_class])
    create index("analytics_events", [:zone_name])
    
    # Composite index for filtering
    create index("analytics_events", [:device_id, :event_type, :event_time])
  end
end
