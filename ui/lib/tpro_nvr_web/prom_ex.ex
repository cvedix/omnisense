defmodule TProNVRWeb.PromEx do
  @moduledoc false

  use PromEx, otp_app: :tpro_nvr

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      TProNVRWeb.PromEx.Device,
      TProNVRWeb.PromEx.Recording,
      TProNVRWeb.PromEx.DeviceStream,
      TProNVRWeb.PromEx.SystemStatus
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "t4C1gkoPQfzLdYMc",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
