defmodule TProNVRWeb.LiveDashboardLive do
  @moduledoc """
  LiveView for Live View page: full-screen camera grid.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.Devices

  @grid_presets [
    %{label: "1×1", cols: 1},
    %{label: "2×2", cols: 2},
    %{label: "3×3", cols: 3},
    %{label: "4×4", cols: 4}
  ]

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-14 left-0 right-0 bottom-0 sm:left-64 flex flex-col overflow-hidden bg-black">

      <%!-- Topbar --%>
      <div class="flex items-center justify-between px-4 py-2 bg-black border-b border-green-700 flex-shrink-0">
        <div class="flex items-center gap-2">
          <.icon name="hero-video-camera-solid" class="w-4 h-4 text-green-500" />
          <span class="text-white text-sm font-semibold">Live View</span>
          <span class="text-green-800">|</span>
          <span class="text-white/40 text-xs">
            <%= length(@devices) %> / <%= length(@all_devices) %> camera
          </span>
        </div>
        <div class="flex items-center gap-1 bg-green-950/60 border border-green-800 rounded-md px-1 py-0.5">
          <button
            :for={preset <- @grid_presets}
            phx-click="set_grid"
            phx-value-cols={preset.cols}
            class={[
              "px-2 py-0.5 text-xs rounded transition-colors font-medium",
              if(@grid_cols == preset.cols,
                do: "bg-green-600 text-white shadow-sm",
                else: "text-white/50 hover:text-white hover:bg-green-800/60")
            ]}
          >
            <%= preset.label %>
          </button>
        </div>
      </div>

      <%!-- Camera Grid --%>
      <div class="flex-1 p-1 overflow-hidden">
        <div
          class="grid gap-1 h-full w-full"
          style={"grid-template-columns: repeat(#{@grid_cols}, 1fr); grid-template-rows: repeat(#{@grid_cols}, 1fr);"}
        >
          <%= for index <- 0..(@grid_cols * @grid_cols - 1) do %>
            <% device = Enum.at(@devices, index) %>
            <div class="relative bg-black rounded-lg overflow-hidden border border-green-800">
              <%= if device do %>
                <video
                  id={"video-#{device.id}"}
                  class="absolute inset-0 w-full h-full object-contain"
                  autoplay
                  muted
                  playsinline
                  phx-hook="HLSPlayer"
                  data-device-id={device.id}
                />
                <div
                  id={"loading-#{device.id}"}
                  class="absolute inset-0 flex items-center justify-center bg-black/60"
                >
                  <.icon name="hero-video-camera" class="w-8 h-8 text-green-500 animate-pulse" />
                </div>
                <div
                  :if={device.state == :failed}
                  class="absolute inset-0 flex items-center justify-center bg-black/80"
                >
                  <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-yellow-500" />
                </div>
                <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/90 to-transparent px-2 py-1.5">
                  <div class="flex items-center justify-between">
                    <span class="text-white text-xs font-medium truncate"><%= device.name %></span>
                    <span class={["px-1.5 py-0.5 text-xs font-bold rounded", status_badge_class(device.state)]}>
                      <%= status_text(device.state) %>
                    </span>
                  </div>
                </div>
                <.link
                  navigate={~p"/dashboard?device_id=#{device.id}"}
                  class="absolute inset-0 z-10"
                ><span></span></.link>
              <% else %>
                <div class="absolute inset-0 flex items-center justify-center">
                  <.icon name="hero-video-camera" class="w-10 h-10 text-green-900" />
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Mount & Params ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TProNVR.PubSub, "devices")
    end

    all_devices = Devices.list(state: [:stopped, :streaming, :recording, :failed])

    {:ok,
     assign(socket,
       all_devices: all_devices,
       devices: all_devices,
       grid_cols: 2,
       grid_presets: @grid_presets
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    all_devices = socket.assigns.all_devices

    {devices, grid_cols} =
      case Map.get(params, "cameras") do
        nil ->
          {all_devices, socket.assigns.grid_cols}

        cameras_str ->
          ids = String.split(cameras_str, ",") |> Enum.map(&String.trim/1)
          filtered = Enum.filter(all_devices, &(&1.id in ids))
          {filtered, filtered |> length() |> auto_grid_cols()}
      end

    {:noreply, assign(socket, devices: devices, grid_cols: grid_cols)}
  end

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("set_grid", %{"cols" => cols}, socket) do
    {:noreply, assign(socket, grid_cols: String.to_integer(cols))}
  end

  # ── PubSub ────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:device_updated, _device}, socket) do
    all_devices = Devices.list(state: [:stopped, :streaming, :recording, :failed])

    {:noreply, assign(socket, all_devices: all_devices, devices: all_devices)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp auto_grid_cols(count) when count <= 1, do: 1
  defp auto_grid_cols(count) when count <= 4, do: 2
  defp auto_grid_cols(count) when count <= 9, do: 3
  defp auto_grid_cols(_), do: 4

  defp status_badge_class(:recording), do: "bg-red-600 text-white"
  defp status_badge_class(:streaming), do: "bg-green-600 text-white"
  defp status_badge_class(:stopped), do: "bg-green-800 text-white"
  defp status_badge_class(:failed), do: "bg-yellow-600 text-black"
  defp status_badge_class(_), do: "bg-green-800 text-white"

  defp status_text(:recording), do: "REC"
  defp status_text(:streaming), do: "LIVE"
  defp status_text(:stopped), do: "OFF"
  defp status_text(:failed), do: "FAIL"
  defp status_text(_), do: "?"
end
