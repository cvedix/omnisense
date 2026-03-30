defmodule TProNVR.Repo.Migrations.AddPositionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :position, :string
    end
  end
end
