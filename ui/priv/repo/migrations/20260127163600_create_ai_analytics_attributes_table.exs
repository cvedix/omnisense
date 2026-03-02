defmodule TProNVR.Repo.Migrations.CreateAIAnalyticsAttributesTable do
  use Ecto.Migration

  def change do
    create table(:ai_analytics_attributes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all)
      add :instance_id, :string
      
      # Attribute data
      add :name, :string, null: false
      add :value, :text
      
      # Reference to tracking object
      add :ref_tracking_id, :string
      
      # Timestamps from source
      add :event_timestamp_ms, :bigint
      add :system_datetime, :utc_datetime_usec
      add :system_timestamp, :bigint
      
      # Raw JSON
      add :raw_data, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ai_analytics_attributes, [:device_id])
    create index(:ai_analytics_attributes, [:instance_id])
    create index(:ai_analytics_attributes, [:name])
    create index(:ai_analytics_attributes, [:ref_tracking_id])
    create index(:ai_analytics_attributes, [:inserted_at])
  end
end
