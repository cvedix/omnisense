defmodule TProNVR.Repo.Migrations.RenameCvedixInstanceIdColumn do
  use Ecto.Migration

  def up do
    # Check if old column exists before renaming
    result = repo().query!("PRAGMA table_info(intrusion_areas)")
    
    has_old_column = Enum.any?(result.rows, fn row ->
      Enum.at(row, 1) == "cvedia_instance_id"
    end)
    
    if has_old_column do
      rename table(:intrusion_areas), :cvedia_instance_id, to: :cvedix_instance_id
    end
  end

  def down do
    # No-op
  end
end

