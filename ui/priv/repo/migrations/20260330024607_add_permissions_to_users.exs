defmodule TProNVR.Repo.Migrations.AddPermissionsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :permissions, {:array, :string}, default: [], null: false
    end
  end
end
