defmodule TProNVR.Repo.Migrations.CreateCameraGroups do
  use Ecto.Migration

  def change do
    create table(:camera_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer, default: 0, null: false

      timestamps()
    end

    create index(:camera_groups, [:position])
  end
end
