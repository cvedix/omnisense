defmodule TProNVRWeb.SystemDashboardLive do
  use TProNVRWeb, :live_view

  alias TProNVR.Devices
  alias TProNVR.CVEDIX
  alias TProNVR.Repo
  alias TProNVR.CVEDIX.AIAnalyticsEvent
  
  import Ecto.Query

  @config_path "/home/cvedix/Documents/Github/omnimedia/release/linux/Debug/config.ini"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to device events if needed
      # TProNVRWeb.Endpoint.subscribe("device_events")
    end

    devices = Devices.list()
    total_devices = length(devices)
    online_devices = Enum.count(devices, fn d -> d.state in [:recording, :streaming] end)
    offline_devices = total_devices - online_devices

    pipelines = length(CVEDIX.list_instances() || [])
    
    commander_synced = is_watchdog_active()

    maps = TProNVR.EMaps.list_maps()

    socket =
      socket
      |> assign(
        total_devices: total_devices,
        online_devices: online_devices,
        offline_devices: offline_devices,
        active_pipelines: pipelines,
        commander_synced: commander_synced,
        page_title: "System Overview",
        maps: maps
      )
      |> load_map_at_index(0)

    {:ok, socket}
  end

  @impl true
  def handle_event("next_map", _, socket) do
    {:noreply, load_map_at_index(socket, socket.assigns.current_map_index + 1)}
  end

  @impl true
  def handle_event("prev_map", _, socket) do
    {:noreply, load_map_at_index(socket, socket.assigns.current_map_index - 1)}
  end

  defp load_map_at_index(socket, index) do
    maps = socket.assigns.maps
    
    if length(maps) > 0 do
      valid_index = rem(index + length(maps), length(maps))
      map = Enum.at(maps, valid_index)
      
      floor_plan_url = "/uploads/#{map["filename"]}?v=#{System.system_time(:second)}"
      map_id = map["id"]
      
      devices = Devices.list()
      placed_devices = Enum.filter(devices, fn d -> d.settings && d.settings.emap_id == map_id && d.settings.emap_x != nil end)
      placed_cameras_count = length(placed_devices)
      
      assign(socket, 
        current_map_index: valid_index,
        current_map_name: map["name"],
        floor_plan_url: floor_plan_url,
        placed_cameras: placed_cameras_count,
        placed_devices: placed_devices,
        event_counts: get_device_event_counts()
      )
    else
      assign(socket,
        current_map_index: 0,
        current_map_name: nil,
        floor_plan_url: nil,
        placed_cameras: 0,
        placed_devices: [],
        event_counts: %{}
      )
    end
  end

  defp get_device_event_counts do
    start_date = DateTime.add(DateTime.utc_now(), -24, :hour)
    
    event_counts_raw = Repo.all(
      from e in AIAnalyticsEvent,
      where: e.inserted_at >= ^start_date,
      group_by: e.device_id,
      select: {e.device_id, count(e.id)}
    )
    Map.new(event_counts_raw)
  end
  
  defp is_watchdog_active do
    if File.exists?(@config_path) do
      content = File.read!(@config_path)
      case Regex.run(~r/^[ \t]*enable[ \t]*=[ \t]*(.*)$/m, content) do
        [_, "1"] -> true
        _ -> false
      end
    else
      false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full bg-black font-mono text-green-500 p-4 md:p-8 overflow-y-auto">
      
      <div class="mb-8 flex items-center justify-between border-b border-green-900/50 pb-4">
        <h1 class="text-2xl font-bold tracking-widest uppercase flex items-center">
          <.icon name="hero-cpu-chip-solid" class="w-8 h-8 mr-3 text-green-500" />
          [ OMNISENSE NVR OVERVIEW ]
        </h1>
        <div class="text-xs tracking-widest uppercase text-green-700">
          NODE_STATUS: <span class="bg-green-500 text-black px-2 py-0.5 font-bold ml-1">OPERATIONAL</span>
        </div>
      </div>

      <!-- KPI Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6 mb-8">
        <!-- Devices KPI -->
        <div class="relative bg-black border border-green-800 p-5 shadow-[0_0_15px_rgba(34,197,94,0.1)] group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs uppercase tracking-widest text-green-600 font-bold">Total Assets</h3>
            <.icon name="hero-video-camera-solid" class="w-5 h-5 text-green-500 opacity-80" />
          </div>
          <div class="text-4xl font-black tracking-tighter text-white mb-2 group-hover:text-green-400 transition-colors">
            <span class={if @total_devices > 0 and @online_devices == @total_devices, do: "text-green-500", else: "text-white"}>{@online_devices}</span><span class="text-white/40 text-2xl mx-1">/</span><span class="text-white/80 text-3xl">{@total_devices}</span>
          </div>
          <div class="flex space-x-4 text-[10px] tracking-widest uppercase">
            <span class="text-green-500 flex items-center"><div class="w-1.5 h-1.5 bg-green-500 rounded-full mr-1"></div> {@online_devices} Online</span>
            <span class="text-red-500 flex items-center"><div class="w-1.5 h-1.5 bg-red-500 rounded-full mr-1"></div> {@offline_devices} Offline</span>
          </div>
        </div>

        <!-- AI Pipelines KPI -->
        <div class="relative bg-black border border-green-800 p-5 shadow-[0_0_15px_rgba(34,197,94,0.1)] group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs uppercase tracking-widest text-green-600 font-bold">Active AI Engines</h3>
            <.icon name="hero-sparkles-solid" class="w-5 h-5 text-yellow-500 opacity-80" />
          </div>
          <div class="text-4xl font-black tracking-tighter text-white mb-2 group-hover:text-yellow-400 transition-colors">{@active_pipelines}</div>
          <div class="text-[10px] tracking-widest uppercase text-green-700">
            Running isolated CVEDIX instances
          </div>
        </div>

        <!-- Commander KPI -->
        <div class="relative bg-black border border-green-800 p-5 shadow-[0_0_15px_rgba(34,197,94,0.1)] group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs uppercase tracking-widest text-green-600 font-bold">Commander Uplink</h3>
            <.icon name="hero-signal-solid" class={["w-5 h-5 opacity-80", if(@commander_synced, do: "text-green-500", else: "text-red-500")]} />
          </div>
          <div class={["text-2xl font-black tracking-tighter mb-2 uppercase break-all", if(@commander_synced, do: "text-green-400", else: "text-red-500")]}>
            {if @commander_synced, do: "CONNECTED", else: "OFFLINE"}
          </div>
          <div class="text-[10px] tracking-widest uppercase text-green-700">
            Central Traccar Telemetry Sync
          </div>
        </div>

        <!-- System Uptime KPI -->
        <div class="relative bg-black border border-green-800 p-5 shadow-[0_0_15px_rgba(34,197,94,0.1)] group hover:border-green-500 transition-colors">
          <div class="absolute top-0 left-0 w-2 h-2 border-t border-l border-green-500"></div>
          <div class="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-green-500"></div>
          
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs uppercase tracking-widest text-green-600 font-bold">Disk Usage</h3>
            <.icon name="hero-server-stack-solid" class="w-5 h-5 text-green-500 opacity-80" />
          </div>
          <div class="text-4xl font-black tracking-tighter text-white mb-2 group-hover:text-green-400 transition-colors">{Float.round((@system_metrics.disk_usage || 0) * 1.0, 1)}%</div>
          <div class="w-full bg-green-900/30 h-1 mt-3 rounded-none overflow-hidden">
            <div class={["h-full", 
               if((@system_metrics.disk_usage || 0) > 90, do: "bg-red-500", 
               else: if((@system_metrics.disk_usage || 0) > 75, do: "bg-yellow-500", else: "bg-green-500"))
            ]} style={"width: #{@system_metrics.disk_usage || 0}%"}></div>
          </div>
        </div>
      </div>

      <!-- Hardware Telemetry Dashboard -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        <div class="relative bg-black border border-green-800 p-6 shadow-[0_0_15px_rgba(34,197,94,0.1)]">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          
          <h2 class="text-sm font-bold tracking-widest uppercase text-green-500 mb-6 flex items-center border-b border-green-900/50 pb-2">
            <.icon name="hero-command-line-solid" class="w-4 h-4 mr-2" />
            Hardware Telemetry
          </h2>
          
          <div class="space-y-6">
            <!-- CPU Row -->
            <div>
              <div class="flex justify-between text-xs tracking-widest uppercase mb-2">
                <span class="font-bold text-green-400">CPU Usage</span>
                <span class="text-white">{Float.round((@system_metrics.cpu_usage || 0) * 1.0, 1)}%</span>
              </div>
              <div class="w-full bg-green-900/30 h-2 rounded-none overflow-hidden border border-green-900/50">
                <div class={["h-full transition-all duration-1000", 
                   if((@system_metrics.cpu_usage || 0) > 85, do: "bg-red-500", 
                   else: if((@system_metrics.cpu_usage || 0) > 60, do: "bg-yellow-500", else: "bg-green-500"))
                ]} style={"width: #{@system_metrics.cpu_usage || 0}%"}></div>
              </div>
            </div>
            
            <!-- RAM Row -->
            <div>
              <div class="flex justify-between text-xs tracking-widest uppercase mb-2">
                <span class="font-bold text-green-400">Memory (RAM)</span>
                <span class="text-white">{Float.round((@system_metrics.ram_usage || 0) * 1.0, 1)}%</span>
              </div>
              <div class="w-full bg-green-900/30 h-2 rounded-none overflow-hidden border border-green-900/50">
                <div class={["h-full transition-all duration-1000", 
                   if((@system_metrics.ram_usage || 0) > 85, do: "bg-red-500", 
                   else: if((@system_metrics.ram_usage || 0) > 70, do: "bg-yellow-500", else: "bg-green-500"))
                ]} style={"width: #{@system_metrics.ram_usage || 0}%"}></div>
              </div>
            </div>
            
            <!-- Temperature Row -->
            <div :if={@system_metrics.cpu_temp}>
              <div class="flex justify-between text-xs tracking-widest uppercase mb-2">
                <span class="font-bold text-green-400">Core Temp</span>
                <span class={["font-bold", if(@system_metrics.cpu_temp > 75, do: "text-red-500", else: "text-white")]}>{@system_metrics.cpu_temp} °C</span>
              </div>
              <div class="w-full bg-green-900/30 h-2 rounded-none overflow-hidden border border-green-900/50">
                <div class={["h-full transition-all duration-1000", 
                   if(@system_metrics.cpu_temp > 80, do: "bg-red-500", 
                   else: if(@system_metrics.cpu_temp > 65, do: "bg-yellow-500", else: "bg-green-500"))
                ]} style={"width: #{min((@system_metrics.cpu_temp / 100) * 100, 100)}%"}></div>
              </div>
            </div>
            
          </div>
        </div>

        <div class="relative bg-black border border-green-800 p-6 shadow-[0_0_15px_rgba(34,197,94,0.1)] flex flex-col">
          <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-green-500"></div>
          <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-green-500"></div>
          
          <h2 class="text-sm font-bold tracking-widest uppercase text-green-500 mb-6 flex items-center border-b border-green-900/50 pb-2 justify-between">
            <div class="flex items-center">
              <.icon name="hero-map-solid" class="w-4 h-4 mr-2" />
              Interactive E-Map
              <%= if assigns[:current_map_name] do %>
                <span class="ml-2 text-white bg-green-900/40 border border-green-900 px-2 py-0.5 text-[10px] rounded-sm truncate max-w-[150px]">{@current_map_name}</span>
              <% end %>
            </div>
            
            <div class="flex items-center">
              <%= if length(@maps) > 1 do %>
                <div class="flex items-center bg-black border border-green-900 rounded-sm overflow-hidden mr-3">
                  <button phx-click="prev_map" class="text-green-500 hover:text-white hover:bg-green-900/50 px-2 h-6 flex items-center transition-colors border-r border-green-900">
                    <.icon name="hero-chevron-left-solid" class="w-3 h-3 block" />
                  </button>
                  <div class="text-[10px] text-green-500 font-bold px-2 h-6 flex items-center bg-green-900/20">
                    {@current_map_index + 1} / {length(@maps)}
                  </div>
                  <button phx-click="next_map" class="text-green-500 hover:text-white hover:bg-green-900/50 px-2 h-6 flex items-center transition-colors border-l border-green-900">
                    <.icon name="hero-chevron-right-solid" class="w-3 h-3 block" />
                  </button>
                </div>
              <% end %>
              <.link href={~p"/emap"} class="text-[10px] bg-green-900/40 border border-green-900 hover:border-green-500 hover:bg-green-500 hover:text-black px-2 py-1 transition-all rounded-sm flex-shrink-0">
                OPEN DIRECTORY
              </.link>
            </div>
          </h2>
          
          <%= if @floor_plan_url do %>
            <div class="flex-1 border border-green-900/30 bg-green-900/10 mb-4 overflow-hidden relative group rounded-sm shadow-inner cursor-pointer" phx-click={JS.navigate(~p"/emap")}>
              <div class="absolute inset-0 bg-black/60 z-20 flex flex-col items-center justify-center backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-opacity">
                <span class="text-green-400 font-bold mb-1 text-2xl">{@placed_cameras} <span class="text-green-800 text-lg">/</span> {@total_devices}</span>
                <span class="text-[10px] text-green-600 uppercase tracking-widest">Cameras Mapped</span>
              </div>
              
              <div class="absolute inset-0 z-10">
                <%= for device <- @placed_devices do %>
                  <% count = @event_counts[device.id] || 0 %>
                  <div class="absolute w-2 h-2 -ml-1 -mt-1" style={"left: #{device.settings.emap_x}%; top: #{device.settings.emap_y}%;"} title={device.name <> " - " <> Atom.to_string(device.state)}>
                    <div class={["w-2 h-2 rounded-full animate-pulse",
                                 if(device.state in [:recording, :streaming], do: "bg-green-500 shadow-[0_0_5px_rgba(34,197,94,1)]", else: "bg-red-500 shadow-[0_0_5px_rgba(239,68,68,1)]")]}>
                    </div>
                    
                    <!-- Notification Badge (Events) relative to the dot -->
                    <%= if count > 0 do %>
                      <div class="absolute -top-3 -right-3 flex items-center justify-center min-w-[14px] h-[14px] bg-red-600 text-white text-[8px] font-bold rounded-full px-0.5 z-30 shadow-[0_0_5px_rgba(220,38,38,0.8)] border border-red-800/50 pointer-events-none transform scale-90">
                        {if count > 99, do: "99+", else: count}
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <img src={@floor_plan_url} class="w-full h-full object-cover opacity-40 block transition-transform duration-700" />
            </div>
          <% else %>
            <div class="flex-1 flex flex-col justify-center text-center border border-dashed border-green-900/50 hover:border-green-500/50 transition-colors mb-4 p-4 rounded-sm">
              <.icon name="hero-map" class="w-8 h-8 text-green-900 mx-auto mb-2" />
              <div class="text-green-700 tracking-widest uppercase font-bold text-[10px] mt-2">No Blueprint Uploaded</div>
            </div>
          <% end %>
          
          <div class="text-[10px] text-green-700 uppercase tracking-widest text-center">
            Floor Plan & Camera Topology Status
          </div>
        </div>
      </div>
    </div>
    """
  end
end
