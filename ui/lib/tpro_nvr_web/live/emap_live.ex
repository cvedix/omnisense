defmodule TProNVRWeb.EMapLive do
  use TProNVRWeb, :live_view

  alias TProNVR.Devices
  alias TProNVR.EMaps

  @upload_dir Path.join(:code.priv_dir(:tpro_nvr), "static/uploads")

  @impl true
  def mount(_params, _session, socket) do
    File.mkdir_p!(@upload_dir)

    maps = EMaps.list_maps()
    current_map_id = if length(maps) > 0, do: List.first(maps)["id"], else: nil

    socket =
      socket
      |> assign(
        maps: maps,
        current_map_id: current_map_id,
        view_device: nil,
        page_title: "Smart E-Map",
        map_name_input: "",
        show_sidebar: true
      )
      |> allow_upload(:floor_plan, accept: ~w(.png .jpg .jpeg .webp), max_entries: 1)
      |> reload_devices()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, show_sidebar: !socket.assigns.show_sidebar)}
  end

  @impl true
  def handle_event("validate", %{"map_name" => name}, socket) do
    {:noreply, assign(socket, map_name_input: name)}
  end

  @impl true
  def handle_event("create_map", %{"map_name" => name}, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :floor_plan, fn %{path: path}, entry ->
        ext = extname(entry.client_name)
        new_filename = "floor_plan_#{Ecto.UUID.generate()}#{ext}"
        dest = Path.join(@upload_dir, new_filename)
        File.cp!(path, dest)
        {:ok, new_filename}
      end)

    if length(uploaded_files) > 0 do
      filename = List.first(uploaded_files)
      {:ok, new_map} = EMaps.create_map(name, filename)

      socket =
        socket
        |> assign(maps: EMaps.list_maps(), current_map_id: new_map["id"], map_name_input: "")
        |> reload_devices()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_map", %{"id" => id}, socket) do
    {:noreply, socket |> assign(current_map_id: id) |> reload_devices()}
  end

  @impl true
  def handle_event("remove_map", _params, socket) do
    id = socket.assigns.current_map_id
    if id do
      EMaps.delete_map(id)

      # Cleanup orphaned devices
      Devices.list()
      |> Enum.each(fn d ->
        if d.settings && d.settings.emap_id == id do
          new_settings = Map.merge(Map.from_struct(d.settings) |> Map.drop([:__meta__]), %{emap_id: nil, emap_x: nil, emap_y: nil, emap_rotation: nil})
          Devices.update(d, %{settings: new_settings})
        end
      end)

      maps = EMaps.list_maps()
      new_id = if length(maps) > 0, do: List.first(maps)["id"], else: nil

      socket =
        socket
        |> assign(maps: maps, current_map_id: new_id)
        |> reload_devices()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("place_camera", %{"device_id" => id, "x" => x, "y" => y}, socket) do
    device = Devices.get!(id)
    map_id = socket.assigns.current_map_id
    
    if map_id do
      new_settings =
        (device.settings || %{})
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.merge(%{emap_id: map_id, emap_x: x, emap_y: y})

      Devices.update(device, %{settings: new_settings})
      {:noreply, reload_devices(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_camera_position", %{"device_id" => id, "x" => x, "y" => y}, socket) do
    device = Devices.get!(id)
    new_settings =
      device.settings
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.merge(%{emap_x: x, emap_y: y})

    Devices.update(device, %{settings: new_settings})
    {:noreply, reload_devices(socket)}
  end

  @impl true
  def handle_event("update_camera_rotation", %{"device_id" => id, "rotation" => r}, socket) do
    device = Devices.get!(id)
    new_settings =
      device.settings
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.merge(%{emap_rotation: r})

    Devices.update(device, %{settings: new_settings})
    {:noreply, reload_devices(socket)}
  end

  @impl true
  def handle_event("remove_camera", %{"device_id" => id}, socket) do
    device = Devices.get!(id)
    new_settings =
      device.settings
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.merge(%{emap_id: nil, emap_x: nil, emap_y: nil, emap_rotation: nil})

    Devices.update(device, %{settings: new_settings})
    {:noreply, reload_devices(socket)}
  end

  @impl true
  def handle_event("view_camera", %{"device_id" => id}, socket) do
    device = Devices.get!(id)
    {:noreply, assign(socket, view_device: device)}
  end

  @impl true
  def handle_event("close_view", _params, socket) do
    {:noreply, assign(socket, view_device: nil)}
  end

  defp reload_devices(socket) do
    devices = Devices.list()
    map_id = socket.assigns.current_map_id

    unplaced = Enum.filter(devices, fn d ->
      d.settings == nil || d.settings.emap_id == nil
    end)

    placed = Enum.filter(devices, fn d ->
      d.settings && d.settings.emap_id == map_id && d.settings.emap_x != nil
    end)

    assign(socket, placed_devices: placed, unplaced_devices: unplaced)
  end

  defp extname(filename) do
    case Path.extname(filename) do
      "" -> ".png"
      ext -> String.downcase(ext)
    end
  end

  @impl true
  def render(assigns) do
    current_map = Enum.find(assigns.maps, fn m -> m["id"] == assigns.current_map_id end)
    floor_plan_url = if current_map, do: "/uploads/#{current_map["filename"]}?v=#{System.system_time(:second)}", else: nil

    assigns = assign(assigns, current_map: current_map, floor_plan_url: floor_plan_url)

    ~H"""
    <div class="h-screen bg-black font-mono text-green-500 overflow-hidden flex flex-col">
      <!-- Header with Tabs -->
      <div class="flex-none p-4 border-b border-green-900/50 flex flex-col md:flex-row items-start md:items-center justify-between">
        <h1 class="text-2xl font-bold tracking-widest uppercase flex items-center mb-4 md:mb-0">
          <.icon name="hero-map-solid" class="w-8 h-8 mr-3 text-green-500" />
          [ SYSTEM E-MAP ]
        </h1>
        
        <!-- Map Tabs -->
        <div class="flex space-x-2 overflow-x-auto w-full md:w-auto pb-2 md:pb-0 items-center">
          <%= for map <- @maps do %>
            <button phx-click="select_map" phx-value-id={map["id"]} 
                    class={["px-4 py-2 text-xs font-bold uppercase tracking-widest whitespace-nowrap transition-colors border",
                            if(@current_map_id == map["id"], do: "bg-green-500 text-black border-green-500", else: "bg-black text-green-500 border-green-900 hover:border-green-500 hover:text-green-300")]}>
              {map["name"]}
            </button>
          <% end %>
          <div class="text-xs tracking-widest uppercase text-green-700 ml-4 flex items-center shrink-0">
            MODE: <span class="bg-green-500 text-black px-2 py-0.5 font-bold ml-1">INTERACTIVE</span>
          </div>
          <button phx-click="toggle_sidebar" class="ml-4 p-1.5 bg-black border border-green-900 hover:border-green-500 text-green-500 hover:text-green-300 transition-colors" title={if @show_sidebar, do: "Hide Asset Inventory", else: "Show Asset Inventory"}>
            <.icon name="hero-arrows-right-left-solid" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex-1 flex overflow-hidden">
        
        <!-- Sidebar: Unplaced Cameras & Controls -->
        <%= if @show_sidebar do %>
        <div class="w-80 bg-black border-r border-green-900/50 flex flex-col p-4 z-10 shrink-0">
          <h2 class="text-sm font-bold uppercase tracking-widest text-green-400 mb-4 border-b border-green-900/30 pb-2">
            Asset Inventory
          </h2>
          
          <p class="text-[10px] text-green-700 mb-4 tracking-widest">
            Drag and drop available cameras onto the selected blueprint to pinpoint locations.
          </p>
          
          <div class="flex-1 overflow-y-auto space-y-3 pb-4" id="unplaced-list">
            <%= if @unplaced_devices == [] do %>
              <div class="text-center p-4 border border-dashed border-green-900 text-green-700 text-xs mt-4">
                No unplaced assets globally.
              </div>
            <% end %>

            <%= for device <- @unplaced_devices do %>
              <div class="bg-green-900/20 border border-green-800 p-3 cursor-grab hover:bg-green-900/40 hover:border-green-500 transition-colors"
                   draggable="true" 
                   data-device-id={device.id}
                   ondragstart="event.dataTransfer.setData('device_id', event.target.dataset.deviceId)"
                   id={"unplaced-#{device.id}"}>
                <div class="flex items-center">
                  <.icon name="hero-video-camera-solid" class="w-4 h-4 mr-2 text-green-500" />
                  <span class="text-xs font-bold truncate">{device.name}</span>
                </div>
                <div class="text-[10px] text-white/50 mt-1 uppercase truncate">{device.vendor} - {device.url}</div>
              </div>
            <% end %>
          </div>

          <!-- Floor Plan Controls -->
          <div class="mt-4 pt-4 border-t border-green-900/50">
            <%= if @current_map_id do %>
              <button 
                phx-click="remove_map" 
                data-confirm={"Are you sure you want to delete blueprint '#{@current_map["name"]}'? All cameras placed here will be reset to Unplaced."}
                class="w-full bg-red-900/20 hover:bg-red-900/40 text-red-500 border border-red-900 py-2 text-xs uppercase tracking-widest font-bold transition-colors mb-4">
                <.icon name="hero-trash-solid" class="w-3 h-3 mr-1 inline" />
                Remove Blueprint
              </button>
            <% end %>
            
            <h3 class="text-xs font-bold uppercase text-green-500 mb-2">Create New Blueprint</h3>
            <form id="upload-form" phx-submit="create_map" phx-change="validate">
              <input type="text" name="map_name" value={@map_name_input} required placeholder="Building / Floor Name" 
                     class="w-full bg-black border border-green-800 text-green-500 p-2 text-xs mb-3 outline-none focus:border-green-400" />

              <div class="border border-dashed border-green-800 p-4 text-center hover:border-green-500 transition-colors relative cursor-pointer group" phx-drop-target={@uploads.floor_plan.ref}>
                <.icon name="hero-arrow-up-tray" class="w-6 h-6 mx-auto mb-2 text-green-600 group-hover:text-green-400" />
                <span class="text-xs text-green-600 group-hover:text-green-400">Select PNG/JPEG</span>
                <.live_file_input upload={@uploads.floor_plan} class="absolute inset-0 w-full h-full opacity-0 cursor-pointer" />
              </div>
              
              <%= for entry <- @uploads.floor_plan.entries do %>
                <div class="mt-2 text-xs text-white">
                  {entry.client_name} - {entry.progress}%
                </div>
              <% end %>

              <button type="submit" class="w-full bg-green-600 text-black font-bold uppercase tracking-widest py-2 mt-3 hover:bg-green-500 transition-colors text-xs"
                      disabled={@uploads.floor_plan.entries == [] || @map_name_input == ""}>
                Upload Map
              </button>
            </form>
          </div>
        </div>
        <% end %>

        <!-- E-Map Canvas -->
        <div class="flex-1 bg-[#0a0a0a] relative overflow-hidden" id="emap-container" phx-hook="EMapEditor">
          <%= if @floor_plan_url do %>
            <!-- The Map -->
            <div id="emap-canvas" class="w-full h-full relative" style="overflow: auto;">
              <!-- Container for actual image and markers so they scale together if needed. For now simple absolute bounds. -->
              <div class="relative inline-block min-w-full min-h-full" style="background-image: url('bg-pattern-dark.png');">
                <img src={@floor_plan_url} id="emap-image" class="block max-w-none origin-top-left" style="min-width: 100%; min-height: 100%; object-fit: contain; object-position: center;" draggable="false" />
                
                <!-- Dropped Cameras -->
                <%= for device <- @placed_devices do %>
                  <div class="absolute w-8 h-8 -ml-4 -mt-4 cursor-pointer group emap-marker"
                       style={"left: #{device.settings.emap_x}%; top: #{device.settings.emap_y}%; z-index: #{if @view_device && @view_device.id == device.id, do: 100, else: 10};"}
                       data-device-id={device.id}
                       data-rotation={device.settings.emap_rotation || 0}
                       phx-value-device_id={device.id}>
                    <!-- Camera Icon Tooltip/Name -->
                    <div class={["absolute -top-6 left-1/2 transform -translate-x-1/2 bg-black/80 text-[10px] px-1.5 py-0.5 whitespace-nowrap border opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity", 
                                 if(device.state in [:recording, :streaming], do: "text-green-400 border-green-900", else: "text-red-400 border-red-900")]}>
                      {device.name}
                    </div>
                    
                    <!-- View Cone Simulator (Rotatable) -->
                    <div class="absolute inset-0 pointer-events-none transform transition-transform" style={"transform: rotate(#{device.settings.emap_rotation || 0}deg)"} id={"cone-#{device.id}"}>
                       <div class={["absolute top-1/2 left-1/2 w-0 h-0 border-l-[25px] border-r-[25px] border-t-[50px] border-transparent transform -translate-x-1/2 -translate-y-full origin-bottom",
                                    if(device.state in [:recording, :streaming], do: "border-t-green-500/20", else: "border-t-red-500/20")]}></div>
                    </div>

                    <!-- Camera Core Icon -->
                    <div class={["w-8 h-8 rounded-full bg-black border-2 flex items-center justify-center relative z-10 transform transition-transform hover:scale-110",
                                 if(device.state in [:recording, :streaming], do: "border-green-500 shadow-[0_0_10px_rgba(34,197,94,0.5)]", else: "border-red-500 shadow-[0_0_10px_rgba(239,68,68,0.5)]")]}
                         title="Double click to view, Right click to remove"
                         phx-click="view_camera" phx-value-device_id={device.id}>
                      <.icon name="hero-video-camera-solid" class={["w-4 h-4", if(device.state in [:recording, :streaming], do: "text-green-500", else: "text-red-500")]} />
                    </div>
                    
                    <!-- Rotation Handle (Permanently Visible) -->
                    <div class={["absolute -bottom-6 left-1/2 transform -translate-x-1/2 bg-black border rounded-full p-0.5 hover:text-white cursor-ew-resize z-20 rotation-handle transition-colors",
                                 if(device.state in [:recording, :streaming], do: "border-green-500 text-green-500 hover:bg-green-600 shadow-[0_0_5px_rgba(34,197,94,0.5)]", else: "border-red-500 text-red-500 hover:bg-red-600 shadow-[0_0_5px_rgba(239,68,68,0.5)]")]}
                         title="Drag left/right to rotate camera direction"
                         data-device-id={device.id}>
                      <.icon name="hero-arrow-path-solid" class="w-3 h-3 block" />
                    </div>
                    <!-- Camera Popover Preview -->
                    <%= if @view_device && @view_device.id == device.id do %>
                      <div class="absolute bottom-full mb-4 left-1/2 transform -translate-x-1/2 bg-black border border-green-500 shadow-[0_0_20px_rgba(34,197,94,0.4)] z-[100] rounded overflow-hidden flex flex-col pointer-events-auto cursor-default" style="width: 320px; height: 212px;">
                         <!-- Popover Header (Height: ~32px) -->
                         <div class="flex items-center justify-between p-2 h-8 border-b border-green-900 bg-green-900/30 shrink-0">
                           <span class="text-[10px] font-bold text-green-400 truncate w-4/5 text-center leading-none uppercase tracking-widest">{@view_device.name}</span>
                           <button phx-click="close_view" class="text-green-500 hover:text-white transition-colors" title="Close Preview">
                             <.icon name="hero-x-mark-solid" class="w-3 h-3" />
                           </button>
                         </div>
                         <!-- Popover Player (Height: 180px, exactly 16:9 for 320px width) -->
                         <div class="flex-1 bg-black relative flex items-center justify-center">
                           <div id={"loading-#{@view_device.id}"} class="absolute inset-0 flex items-center justify-center flex-col">
                             <div class="w-6 h-6 border-2 border-green-500 border-t-transparent rounded-full animate-spin mb-2"></div>
                             <span class="text-[10px] text-green-500 tracking-wider">CONNECTING</span>
                           </div>
                           <video 
                             id={"webrtc-player-#{@view_device.id}"}
                             phx-hook="WebRTCPlayer"
                             data-device-id={@view_device.id}
                             data-token={Phoenix.Token.sign(TProNVRWeb.Endpoint, "user socket", "admin")}
                             class="w-full h-full object-contain relative z-10"
                             autoplay 
                             muted 
                             playsinline
                           ></video>
                         </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
            
            <!-- Controls Legend -->
            <div class="absolute bottom-4 left-4 bg-black/80 border border-green-900/50 p-3 pointer-events-none z-10">
              <div class="text-[10px] text-green-500 uppercase tracking-widest font-bold mb-1">E-Map Controls</div>
              <ul class="text-[10px] text-green-700 space-y-1">
                <li>• Drag cameras from Asset list to place</li>
                <li>• Drag placed camera to reposition</li>
                <li>• Click rotation handle to rotate field-of-view</li>
                <li>• Click camera to open Live Stream</li>
                <li>• Right-click camera to remove from map</li>
              </ul>
            </div>
          <% else %>
            <div class="absolute inset-0 flex items-center justify-center">
              <div class="text-center animate-pulse text-green-900">
                <.icon name="hero-map" class="w-24 h-24 mx-auto mb-4 opacity-50" />
                <h2 class="text-xl font-bold uppercase tracking-widest">No Active Blueprint</h2>
                <p class="text-xs mt-2">Use the left panel to upload and create a new map layer.</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
