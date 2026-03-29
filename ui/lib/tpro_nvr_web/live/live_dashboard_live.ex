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
    <!-- We use main-content-offset class here since this layout uses fixed positioning -->
    <div class="fixed top-14 left-0 right-0 bottom-0 main-content-offset-left flex flex-col overflow-hidden bg-black font-mono z-10 transition-all duration-300">

      <%!-- Topbar --%>
      <div class="flex items-center justify-between px-6 py-3 bg-black border-b border-green-900/50 flex-shrink-0 relative">
        <div class="absolute bottom-0 left-0 w-8 h-1 bg-green-500"></div>
        <div class="flex items-center gap-3">
          <.icon name="hero-video-camera-solid" class="w-5 h-5 text-green-500 shadow-[0_0_10px_rgba(34,197,94,0.5)]" />
          <span class="text-green-500 text-sm font-bold tracking-widest uppercase">MODULE: LIVE_VIEW</span>
          <span class="text-green-900 mx-2">|</span>
          <span class="text-green-700 text-xs tracking-widest uppercase">
            SYS_ASSETS: <%= length(@devices) %> / <%= length(@all_devices) %>
          </span>
        </div>
        <div class="flex items-center gap-2">
          <button
            :for={preset <- @grid_presets}
            phx-click="set_grid"
            phx-value-cols={preset.cols}
            class={[
              "px-3 py-1 text-xs rounded-none transition-all font-bold tracking-widest uppercase border border-transparent shadow-inner",
              if(@grid_cols == preset.cols,
                do: "bg-green-500 text-black border-green-500 shadow-[0_0_10px_rgba(34,197,94,0.4)]",
                else: "text-green-700 bg-green-900/10 hover:border-green-500/50 hover:bg-green-900/20 hover:text-green-500")
            ]}
          >
            <%= preset.label %>
          </button>
        </div>
      </div>

      <%!-- Main Workspace --%>
      <div class="flex flex-1 overflow-hidden">
        
        <%!-- Asset Tree Sidebar --%>
        <div class="hidden md:flex flex-col w-64 bg-black border-r border-green-900/50 flex-shrink-0 z-10 shadow-[10px_0_20px_rgba(0,0,0,0.5)]">
          <div class="p-3 border-b border-green-900/50 bg-green-900/10 flex items-center justify-between">
            <span class="text-green-500 font-bold tracking-widest text-[10px] uppercase">SYS_NODE_TREE</span>
            <span class="text-green-700 text-[10px] font-mono"><%= length(@all_devices) %> ASSETS</span>
          </div>
          <div class="flex-1 overflow-y-auto p-2 space-y-1">
            <button
              :for={dev <- @all_devices}
              phx-click="toggle_camera"
              phx-value-id={dev.id}
              class={[
                "w-full text-left p-2 border-l-2 transition-all flex items-center justify-between group",
                if(Enum.any?(@devices, &(&1.id == dev.id)),
                  do: "border-green-500 bg-green-900/30 text-green-400 shadow-[inset_2px_0_10px_rgba(34,197,94,0.2)]",
                  else: "border-green-900/30 bg-black text-green-700 hover:border-green-500/50 hover:bg-green-900/20")
              ]}
            >
              <div class="flex items-center overflow-hidden">
                <.icon name="hero-video-camera" class={["w-4 h-4 mr-2 flex-shrink-0", if(Enum.any?(@devices, &(&1.id == dev.id)), do: "text-green-500", else: "text-green-800 group-hover:text-green-600")]} />
                <span class="text-xs font-bold tracking-widest uppercase truncate"><%= dev.name %></span>
              </div>
              
              <div class="w-2 h-2 rounded-none ml-2 flex-shrink-0 shadow-[0_0_5px_rgba(0,0,0,0.5)]" 
                   class={[
                     dev.state == :streaming && "bg-green-500",
                     dev.state == :recording && "bg-red-500",
                     dev.state == :stopped && "bg-green-900",
                     dev.state == :failed && "bg-yellow-500",
                     "shadow-inner"
                   ]}>
              </div>
            </button>
          </div>
        </div>

        <%!-- Camera Grid --%>
        <div class="flex-1 p-2 overflow-hidden bg-black/90 relative">
          <!-- Background Grid Lines -->
          <div class="absolute inset-0 pointer-events-none opacity-[0.03]" style="background-image: linear-gradient(to right, #22c55e 1px, transparent 1px), linear-gradient(to bottom, #22c55e 1px, transparent 1px); background-size: 40px 40px;"></div>
          
          <div
            class="grid gap-2 h-full w-full relative z-10"
            style={"grid-template-columns: repeat(#{@grid_cols}, 1fr); grid-template-rows: repeat(#{@grid_cols}, 1fr);"}
          >
            <%= for index <- 0..(@grid_cols * @grid_cols - 1) do %>
              <% device = Enum.at(@devices, index) %>
              <div class="relative bg-black rounded-none overflow-hidden border border-green-900/60 group hover:border-green-500 transition-colors shadow-[inset_0_0_20px_rgba(0,128,0,0.05)]">
                <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500 z-20"></div>
                <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500 z-20"></div>
                
                <%= if device do %>
                  <video
                    id={"video-#{device.id}"}
                    class="absolute inset-0 w-full h-full object-contain border-none"
                    autoplay
                    muted
                    playsinline
                    phx-hook="WebRTCPlayer"
                    data-device-id={device.id}
                    data-token={@user_token}
                  />
                  <div
                    id={"loading-#{device.id}"}
                    class="absolute inset-0 flex items-center justify-center bg-black/60 z-10"
                  >
                    <.icon name="hero-video-camera" class="w-8 h-8 text-green-500 animate-pulse shadow-[0_0_15px_rgba(34,197,94,0.3)]" />
                  </div>
                  <div
                    :if={device.state == :failed}
                    class="absolute inset-0 flex items-center justify-center bg-black/80 z-10"
                  >
                    <div class="border border-yellow-500/50 bg-yellow-900/20 p-4 shadow-[0_0_15px_rgba(234,179,8,0.2)]">
                      <.icon name="hero-exclamation-triangle" class="w-10 h-10 text-yellow-500 animate-pulse" />
                    </div>
                  </div>
                  <div class="absolute bottom-0 left-0 right-0 bg-black/80 border-t border-green-900/50 px-3 py-2 z-20 backdrop-blur-sm">
                    <div class="flex items-center justify-between">
                      <span class="text-green-500 text-xs font-bold truncate tracking-widest uppercase"><%= device.name %></span>
                      <span class={["px-2 py-0.5 text-[9px] font-bold rounded-none tracking-widest uppercase border shadow-inner", status_badge_class(device.state)]}>
                        <%= status_text(device.state) %>
                      </span>
                    </div>
                  </div>
                  <.link
                    navigate={~p"/dashboard?device_id=#{device.id}"}
                    class="absolute inset-0 z-30"
                  ><span></span></.link>
                <% else %>
                  <div class="absolute inset-0 flex flex-col items-center justify-center bg-black/50 opacity-30">
                    <.icon name="hero-video-camera" class="w-10 h-10 text-green-900" />
                    <span class="text-green-900 text-[10px] tracking-widest uppercase mt-2">NO_SIGNAL</span>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
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

    user = socket.assigns.current_user
    token = Phoenix.Token.sign(socket, "user socket", user.id)

    {:ok,
     assign(socket,
       all_devices: all_devices,
       devices: all_devices,
       grid_cols: 2,
       grid_presets: @grid_presets,
       user_token: token
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
  def handle_event("toggle_camera", %{"id" => id}, socket) do
    device = Enum.find(socket.assigns.all_devices, &(&1.id == id))
    devices = socket.assigns.devices
    
    new_devices =
      if Enum.any?(devices, &(&1.id == id)) do
        Enum.reject(devices, &(&1.id == id))
      else
        devices ++ [device]
      end

    # Auto-expand grid if needed
    new_grid_cols =
      if length(new_devices) > socket.assigns.grid_cols * socket.assigns.grid_cols do
        auto_grid_cols(length(new_devices))
      else
        socket.assigns.grid_cols
      end

    # Build new URL to update query params if desired
    # We could push_patch to ?cameras=id1,id2
    ids = Enum.map(new_devices, & &1.id) |> Enum.join(",")
    socket = push_patch(socket, to: ~p"/live-view?cameras=#{ids}")

    {:noreply, assign(socket, devices: new_devices, grid_cols: new_grid_cols)}
  end

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

  defp status_badge_class(:recording), do: "bg-red-900/40 border-red-500 text-red-500 shadow-[0_0_5px_rgba(239,68,68,0.3)]"
  defp status_badge_class(:streaming), do: "bg-green-900/40 border-green-500 text-green-400 shadow-[0_0_5px_rgba(34,197,94,0.3)]"
  defp status_badge_class(:stopped),   do: "bg-black border-green-800 text-green-700"
  defp status_badge_class(:failed),    do: "bg-yellow-900/40 border-yellow-500 text-yellow-500 shadow-[0_0_5px_rgba(234,179,8,0.3)]"
  defp status_badge_class(_),          do: "bg-black border-green-800 text-green-700"

  defp status_text(:recording), do: "REC"
  defp status_text(:streaming), do: "LIVE"
  defp status_text(:stopped), do: "OFF"
  defp status_text(:failed), do: "FAIL"
  defp status_text(_), do: "?"
end
