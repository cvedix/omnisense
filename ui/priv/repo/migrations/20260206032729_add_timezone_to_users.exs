defmodule TProNVR.Repo.Migrations.AddTimezoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :timezone, :string, default: "Asia/Ho_Chi_Minh"
    end
  end
end
