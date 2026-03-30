defmodule TProNVR.Repo.Migrations.AddAllowedDevicesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :allowed_device_ids, {:array, :binary_id}, default: [], null: false
    end
  end
end
