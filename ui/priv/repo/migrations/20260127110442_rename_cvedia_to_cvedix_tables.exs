defmodule TProNVR.Repo.Migrations.RenameCvediaToCvedixTables do
  use Ecto.Migration

  def change do
    # Only rename if old table exists (for legacy databases)
    # New installations already have cvedix_instances from the first migration
    execute(
      """
      SELECT CASE WHEN EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='cvedia_instances')
      THEN 1 ELSE 0 END
      """,
      ""
    )
  end

  def up do
    # Check if old table exists before renaming
    result = repo().query!("SELECT name FROM sqlite_master WHERE type='table' AND name='cvedia_instances'")
    
    if result.num_rows > 0 do
      rename table(:cvedia_instances), to: table(:cvedix_instances)
    end
  end

  def down do
    # No-op - we don't want to rename back
  end
end

