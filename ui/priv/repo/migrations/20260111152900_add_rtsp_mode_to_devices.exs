defmodule CVR.Repo.Migrations.AddRtspModeToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      # RTSP routing mode: :direct for compatible cameras, :proxy for Tapo via MediaMTX
      add :rtsp_mode, :string, default: "direct"
      # Auto-generated stream key for MediaMTX proxy (e.g., "tapo_serial123")
      add :proxy_stream_key, :string
    end

    # Add index for quick lookup by stream key
    create index(:devices, [:proxy_stream_key])
  end
end
