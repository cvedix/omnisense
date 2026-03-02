defmodule TProNVR.Repo.Migrations.CreateAIAnalyticsEventsTable do
  use Ecto.Migration

  def change do
    create table(:ai_analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      add :instance_id, :string
      
      # Event type (event-intrusion, event-area-enter, event-area-exit, event-intrusion-end)
      add :event_type, :string, null: false
      
      # Event references
      add :event_id, :string
      add :ref_tracking_id, :string
      add :ref_event_id, :string
      
      # Area info
      add :area_id, :string
      add :area_name, :string
      
      # Detection data
      add :object_class, :string
      add :event_timestamp_ms, :bigint
      
      # Location (bounding box normalized 0-1)
      add :location_x, :float
      add :location_y, :float
      add :location_width, :float
      add :location_height, :float
      
      # Timestamps from source
      add :system_datetime, :utc_datetime_usec
      add :system_timestamp, :bigint
      
      # Raw JSON
      add :raw_data, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ai_analytics_events, [:device_id])
    create index(:ai_analytics_events, [:instance_id])
    create index(:ai_analytics_events, [:event_type])
    create index(:ai_analytics_events, [:area_id])
    create index(:ai_analytics_events, [:ref_tracking_id])
    create index(:ai_analytics_events, [:inserted_at])
  end
end
