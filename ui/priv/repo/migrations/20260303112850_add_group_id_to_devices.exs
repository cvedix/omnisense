defmodule TProNVR.Repo.Migrations.AddGroupIdToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :group_id, references(:camera_groups, type: :binary_id, on_delete: :nilify_all),
        null: true
    end

    create index(:devices, [:group_id])
  end
end
