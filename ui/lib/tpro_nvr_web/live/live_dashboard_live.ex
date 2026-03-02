defmodule TProNVRWeb.LiveDashboardLive do
  @moduledoc """
  LiveView for displaying all cameras in a grid layout with live preview.
  Uses HLS streaming for maximum compatibility and stability.
  """
  use TProNVRWeb, :live_view

  alias TProNVR.Devices

  @grid_presets [
    %{label: "1×1", cols: 1},
    %{label: "2×2", cols: 2},
    %{label: "3×3", cols: 3},
    %{label: "4×4", cols: 4}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-14 left-0 right-0 bottom-0 sm:left-64 bg-black flex flex-col">
      <!-- Grid Controls -->
      <div class="flex items-center justify-between px-4 py-2 bg-black border-b border-green-800">
        <div class="text-white/80 text-sm">
          <%= length(@devices) %> camera(s)
        </div>
        
        <div class="flex items-center gap-2">
          <!-- Preset buttons -->
          <button
            :for={preset <- @grid_presets}
            phx-click="set_grid"
            phx-value-cols={preset.cols}
            class={[
              "px-3 py-1 text-sm rounded transition-colors",
              if(@grid_cols == preset.cols, do: "bg-green-600 text-white", else: "bg-black text-white hover:bg-green-800")
            ]}
          >
            <%= preset.label %>
          </button>
          
          <!-- Custom grid input -->
          <div class="flex items-center gap-1 ml-2">
            <input
              type="number"
              min="1"
              max="16"
              value={@grid_cols}
              phx-change="set_custom_grid"
              name="cols"
              class="w-12 px-2 py-1 text-sm bg-black text-white border border-green-700 rounded text-center"
            />
            <span class="text-white/80 text-sm">×</span>
            <input
              type="number"
              min="1"
              max="16"
              value={@grid_cols}
              disabled
              class="w-12 px-2 py-1 text-sm bg-black text-white/60 border border-green-700 rounded text-center"
            />
          </div>
        </div>
      </div>

      <!-- Camera Grid -->
      <div class="flex-1 p-1 overflow-hidden">
        <div
          class="grid gap-1 h-full w-full"
          style={"grid-template-columns: repeat(#{@grid_cols}, 1fr); grid-template-rows: repeat(#{@grid_cols}, 1fr);"}
        >
          <%= for index <- 0..(@grid_cols * @grid_cols - 1) do %>
            <% device = Enum.at(@devices, index) %>
            <div class="relative bg-black rounded-lg overflow-hidden border border-green-800">
              <%= if device do %>
                <!-- HLS Video Player -->
                <video
                  id={"video-#{device.id}"}
                  class="absolute inset-0 w-full h-full object-contain"
                  autoplay
                  muted
                  playsinline
                  phx-hook="HLSPlayer"
                  data-device-id={device.id}
                />
                
                <!-- Loading overlay -->
                <div
                  id={"loading-#{device.id}"}
                  class="absolute inset-0 flex items-center justify-center bg-black/60"
                >
                  <.icon name="hero-video-camera" class="w-8 h-8 text-green-500 animate-pulse" />
                </div>
                
                <!-- Offline overlay -->
                <div
                  :if={device.state == :failed}
                  class="absolute inset-0 flex items-center justify-center bg-black/80"
                >
                  <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-yellow-500" />
                </div>
                
                <!-- Camera info overlay -->
                <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/90 to-transparent px-3 py-2">
                  <div class="flex items-center justify-between">
                    <span class="text-white text-sm font-medium truncate"><%= device.name %></span>
                    <span class={[
                      "px-2 py-0.5 text-xs font-bold rounded",
                      status_badge_class(device.state)
                    ]}>
                      <%= status_text(device.state) %>
                    </span>
                  </div>
                </div>
                
                <!-- Click to fullscreen -->
                <.link
                  navigate={~p"/dashboard?device_id=#{device.id}"}
                  class="absolute inset-0 z-10"
                ><span></span></.link>
              <% else %>
                <!-- Empty slot -->
                <div class="absolute inset-0 flex items-center justify-center">
                  <.icon name="hero-video-camera" class="w-12 h-12 text-white" />
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TProNVR.PubSub, "devices")
    end

    devices = Devices.list(state: [:stopped, :streaming, :recording, :failed])

    {:ok, assign(socket, 
      devices: devices, 
      grid_cols: 2, 
      grid_presets: @grid_presets
    )}
  end

  @impl true
  def handle_event("set_grid", %{"cols" => cols}, socket) do
    cols = String.to_integer(cols)
    {:noreply, assign(socket, grid_cols: cols)}
  end

  @impl true
  def handle_event("set_custom_grid", %{"cols" => cols}, socket) do
    cols = cols |> String.to_integer() |> max(1) |> min(16)
    {:noreply, assign(socket, grid_cols: cols)}
  end

  @impl true
  def handle_info({:device_updated, _device}, socket) do
    devices = Devices.list(state: [:stopped, :streaming, :recording, :failed])
    {:noreply, assign(socket, devices: devices)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

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
