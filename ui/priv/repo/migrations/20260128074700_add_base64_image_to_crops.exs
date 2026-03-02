defmodule TProNVR.Repo.Migrations.AddBase64ImageToCrops do
  use Ecto.Migration

  def change do
    alter table(:ai_analytics_crops) do
      add :base64_image, :text
    end
  end
end
