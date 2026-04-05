defmodule TProNVRWeb.DeviceTabs.AnalyticsTab do
  @moduledoc """
  LiveComponent for CVEDIX-RT analytics configuration.
  Supports drawing zones and lines directly on HLS video.
  """

  use TProNVRWeb, :live_component

  require Logger

  alias TProNVR.CVEDIX
  alias TProNVR.CVEDIX.Analytics

  # Analytics type definitions - matching reference image
  @zone_types [
    %{id: "intrusion", name: "Intrusion detection", desc: "Detect objects entering a restricted area", icon: "🚨"},
    %{id: "crossing", name: "Area enter/exit", desc: "Track objects entering or exiting an area", icon: "🚪"},
    %{id: "loitering", name: "Loitering", desc: "Detect objects staying too long in an area", icon: "⏱️"},
    %{id: "object_removed", name: "Object guarding", desc: "Detect objects being removed", icon: "🔒"},
    %{id: "object_left", name: "Object left behind", desc: "Detect abandoned objects", icon: "📦"},
    %{id: "crowding", name: "Crowding", desc: "Detect too many objects in an area", icon: "👥"},
    %{id: "occupancy", name: "Occupancy", desc: "Count objects currently in an area", icon: "🔢"},
    %{id: "crowd_estimation", name: "Crowd estimation", desc: "Estimate crowd density", icon: "👨‍👩‍👧‍👦"},
    %{id: "dwelling", name: "Dwelling", desc: "Detect objects stopping in an area", icon: "🛑"},
    %{id: "armed_person", name: "Armed person", desc: "Detect person holding weapon", icon: "⚠️"},
    %{id: "fallen_person", name: "Fallen person", desc: "Detect person who has fallen", icon: "🆘"}
  ]

  @line_types [
    %{id: "tailgating", name: "Tailgating", desc: "Detect multiple objects crossing together", icon: "👫"},
    %{id: "crossing", name: "Line crossing", desc: "Detect objects crossing a virtual line", icon: "➡️"},
    %{id: "counting", name: "Line counting", desc: "Count objects crossing a line by direction", icon: "🔢"}
  ]

  @object_classes ["Person", "Animal", "Vehicle", "Unknown", "Fire", "LPD", "Face"]
  @selectable_classes ["Person", "Animal", "Vehicle", "Unknown"]  # Classes users can select
  @readonly_classes ["Fire", "LPD", "Face"]  # Display-only classes (not selectable)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Header with CVEDIX status and instance controls -->
      <div class="flex justify-between items-center">
        <div class="flex items-center gap-3">
          <h3 class="text-lg font-semibold text-white">Video Analytics</h3>
          <%= if @cvedix_status == :connected do %>
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
              <span class="w-2 h-2 bg-green-400 rounded-full mr-1"></span>
              Connected
            </span>
          <% else %>
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
              <span class="w-2 h-2 bg-red-400 rounded-full mr-1"></span>
              Offline
            </span>
          <% end %>
        </div>
        <div class="flex gap-2 items-center">
          <%= if @instance do %>
            <span class={"text-sm font-medium #{status_color(@instance.status)}"}><%= String.upcase(@instance.status) %></span>
            <%= if @instance.status == "running" do %>
              <button phx-click="stop_instance" phx-target={@myself}
                class="px-3 py-1 bg-red-600 hover:bg-red-700 text-white rounded text-xs">Stop</button>
            <% else %>
              <button phx-click="start_instance" phx-target={@myself}
                class="px-3 py-1 bg-green-600 hover:bg-green-700 text-white rounded text-xs">Start</button>
            <% end %>
            <button phx-click="toggle_settings" phx-target={@myself}
              class={"px-3 py-1 rounded text-xs #{if @show_settings, do: "bg-yellow-600 hover:bg-yellow-700", else: "bg-green-800 hover:bg-green-700"} text-white"}>
              ⚙️ Settings
            </button>
            <button phx-click="remove_instance" phx-target={@myself} data-confirm="Remove instance?"
              class="px-3 py-1 bg-green-800 hover:bg-green-700 text-white rounded text-xs">Remove</button>
          <% else %>
            <button phx-click="create_instance" phx-target={@myself}
              disabled={@cvedix_status != :connected}
              class="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white rounded text-sm disabled:opacity-50">
              Enable Analytics
            </button>
          <% end %>
        </div>
      </div>

      <!-- Drawing mode indicator (above video) -->
      <%= if @drawing_mode do %>
        <div class="flex items-center gap-2 bg-yellow-500 text-black px-3 py-2 rounded-lg text-sm font-medium mb-3">
          <%= if @drawing_mode == "zone" do %>
            🎯 Click to add points (min 3), then click "Finish"
          <% else %>
            📏 Click for points (min 2), then click "Finish"
          <% end %>
          <button phx-click="finish_drawing" phx-target={@myself}
            class="ml-auto bg-green-600 hover:bg-green-700 text-white px-3 py-1 rounded text-sm font-medium">
            ✓ Finish
          </button>
          <button phx-click="cancel_drawing" phx-target={@myself}
            class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded text-sm">
            Cancel
          </button>
        </div>
      <% end %>


      <!-- Main Content: Video LEFT + Analytics RIGHT -->
      <div class="flex gap-4">
        <!-- LEFT: Video Preview (takes remaining space) -->
        <div class="flex-grow" style="min-width: 0;">
          <div class="relative bg-black rounded-lg overflow-hidden aspect-video">
            <!-- Always use HLS Video for live streaming -->
            <video
              id={"analytics-video-#{@device.id}"}
              class="w-full h-full"
              phx-hook="HLSPlayer"
              data-device-id={@device.id}
              autoplay
              muted
              playsinline
            ></video>

            <!-- Canvas overlay for drawing zones/lines -->
            <canvas
              id={"analytics-canvas-#{@device.id}"}
              phx-hook="AnalyticsDrawing"
              phx-target={@myself}
              data-video-id={"analytics-video-#{@device.id}"}
              class="absolute inset-0 w-full h-full"
              style="pointer-events: auto;"
            ></canvas>

            <!-- Drawing mode indicator (keep this overlay) -->
            
          </div>

          <!-- Zone Configuration Form (below video, shown after drawing complete) -->
          <%= if @pending_coordinates && !@drawing_mode do %>
            <div class="bg-black rounded-lg p-4 mt-3 border border-yellow-500/50">
              <form phx-submit="save_analytics" phx-target={@myself}>
                <!-- Zone Name Input -->
                <div class="mb-4">
                  <label class="text-white text-sm font-medium block mb-2">Zone Name</label>
                  <input type="text" name="name" required 
                    placeholder="Enter zone name..." 
                    value={@pending_name}
                    class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent" />
                </div>

                <!-- Object Type Detection Selection (not for Object Guarding/Object Left Behind/Crowd Estimation) -->
                <%= if @selected_type not in ["zone:object_removed", "zone:object_left", "zone:crowd_estimation"] do %>
                  <div class="mb-4">
                    <p class="text-white text-sm font-medium mb-2">Detection Classes</p>
                    <div class="flex flex-wrap gap-2">
                      <!-- Selectable classes -->
                      <%= for cls <- @selectable_classes do %>
                        <label class={[
                          "flex items-center gap-2 p-2 rounded-lg cursor-pointer transition-all border",
                          if(cls in @selected_classes, 
                            do: "bg-green-600/20 border-green-500 text-white", 
                            else: "bg-black border-green-700 text-white/80 hover:border-green-500 hover:text-white")
                        ]}>
                          <input 
                            type="checkbox" 
                            checked={cls in @selected_classes}
                            phx-click="toggle_class"
                            phx-value-class={cls}
                            phx-target={@myself}
                            class="w-4 h-4 rounded bg-black border-green-700 text-green-500 focus:ring-green-500" 
                          />
                          <span class="text-sm font-medium"><%= cls %></span>
                        </label>
                      <% end %>
                      <!-- Readonly classes (Fire, LPD, Face) -->
                      <%= for cls <- @readonly_classes do %>
                        <label class="flex items-center gap-2 p-2 rounded-lg transition-all border bg-green-900/50 border-green-700 text-white/80 cursor-not-allowed opacity-60">
                          <input 
                            type="checkbox" 
                            checked={false}
                            disabled
                            class="w-4 h-4 rounded bg-green-800 border-green-700 text-white/70 cursor-not-allowed" 
                          />
                          <span class="text-sm font-medium"><%= cls %></span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Loitering/Object Guarding/Object Left Behind: Seconds field -->
                <%= if @selected_type in ["zone:loitering", "zone:object_removed", "zone:object_left"] do %>
                  <div class="mb-4">
                    <%= cond do %>
                      <% @selected_type == "zone:loitering" -> %>
                        <label class="text-white text-sm font-medium block mb-2">Time threshold (seconds)</label>
                        <p class="text-white/60 text-xs mb-2">Alarm will trigger after object stays in area for this duration</p>
                      <% @selected_type == "zone:object_removed" -> %>
                        <label class="text-white text-sm font-medium block mb-2">Alarm if object is missing for more than (seconds)</label>
                        <p class="text-white/60 text-xs mb-2">Alert when guarded object is removed from area</p>
                      <% @selected_type == "zone:object_left" -> %>
                        <label class="text-white text-sm font-medium block mb-2">Alarm if object is left behind for more than (seconds)</label>
                        <p class="text-white/60 text-xs mb-2">Alert when an object is left/abandoned in the area</p>
                    <% end %>
                    <input type="number" name="seconds" 
                      min="1" max="3600" required
                      value={if @selected_type in ["zone:object_removed", "zone:object_left"], do: 4, else: @pending_seconds}
                      class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent" />
                  </div>
                <% end %>

                <!-- Crowding: Object count and seconds -->
                <%= if @selected_type == "zone:crowding" do %>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Maximum number of objects</label>
                    <p class="text-white/60 text-xs mb-2">Alert when number of objects in area exceeds this threshold</p>
                    <input type="number" name="object_count" 
                      min="1" max="100" required
                      value="5"
                      class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent" />
                  </div>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Time threshold (seconds)</label>
                    <p class="text-white/60 text-xs mb-2">Alert after crowding persists for this duration (0 = immediate)</p>
                    <input type="number" name="seconds" 
                      min="0" max="3600" required
                      value="0"
                      class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent" />
                  </div>
                <% end %>

                <!-- Crossing (Area Enter/Exit): Event type and stationary object settings -->
                <%= if @selected_type == "zone:crossing" do %>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Trigger on</label>
                    <select name="area_event" 
                      phx-change="select_area_event"
                      phx-target={@myself}
                      class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent">
                      <%= for {value, label} <- @area_event_options do %>
                        <option value={value} selected={@pending_area_event == value}><%= label %></option>
                      <% end %>
                    </select>
                  </div>
                  <div class="mb-4">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input 
                        type="checkbox" 
                        name="ignore_stationary"
                        checked={@pending_ignore_stationary}
                        phx-click="toggle_ignore_stationary"
                        phx-target={@myself}
                        class="w-4 h-4 rounded bg-black border-green-700 text-green-500 focus:ring-green-500" 
                      />
                      <span class="text-white text-sm">Ignore stationary objects</span>
                    </label>
                    <p class="text-white/60 text-xs mt-1 ml-6">Only detect moving objects entering/exiting the area</p>
                  </div>
                <% end %>

                <!-- Tailgating: Seconds and Direction -->
                <%= if @selected_type == "line:tailgating" do %>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Time threshold (seconds)</label>
                    <p class="text-white/60 text-xs mb-2">How close together objects must be to trigger tailgating</p>
                    <input type="number" name="seconds" 
                      min="1" max="60" required
                      value="4"
                      class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent" />
                  </div>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Detection Direction</label>
                    <p class="text-white/60 text-xs mb-2">Which direction(s) to monitor for tailgating</p>
                    <div class="flex gap-2">
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Up", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Up" 
                          checked={@pending_direction == "Up"}
                          phx-click="select_direction" phx-value-direction="Up" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑</span>
                        <span class="text-sm font-medium">Up</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Down", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Down" 
                          checked={@pending_direction == "Down"}
                          phx-click="select_direction" phx-value-direction="Down" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↓</span>
                        <span class="text-sm font-medium">Down</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Both", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Both" 
                          checked={@pending_direction == "Both"}
                          phx-click="select_direction" phx-value-direction="Both" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑↓</span>
                        <span class="text-sm font-medium">Both</span>
                      </label>
                    </div>
                  </div>
                <% end %>

                <!-- Line Crossing: Direction -->
                <%= if @selected_type == "line:crossing" do %>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Detection Direction</label>
                    <p class="text-white/60 text-xs mb-2">Which direction(s) to detect crossing</p>
                    <div class="flex gap-2">
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Up", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Up" 
                          checked={@pending_direction == "Up"}
                          phx-click="select_direction" phx-value-direction="Up" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑</span>
                        <span class="text-sm font-medium">Up</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Down", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Down" 
                          checked={@pending_direction == "Down"}
                          phx-click="select_direction" phx-value-direction="Down" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↓</span>
                        <span class="text-sm font-medium">Down</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Both", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Both" 
                          checked={@pending_direction == "Both"}
                          phx-click="select_direction" phx-value-direction="Both" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑↓</span>
                        <span class="text-sm font-medium">Both</span>
                      </label>
                    </div>
                  </div>
                <% end %>

                <!-- Line Counting: Direction -->
                <%= if @selected_type == "line:counting" do %>
                  <div class="mb-4">
                    <label class="text-white text-sm font-medium block mb-2">Counting Direction</label>
                    <p class="text-white/60 text-xs mb-2">Which direction(s) to count objects crossing</p>
                    <div class="flex gap-2">
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Up", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Up" 
                          checked={@pending_direction == "Up"}
                          phx-click="select_direction" phx-value-direction="Up" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑</span>
                        <span class="text-sm font-medium">Up</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Down", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Down" 
                          checked={@pending_direction == "Down"}
                          phx-click="select_direction" phx-value-direction="Down" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↓</span>
                        <span class="text-sm font-medium">Down</span>
                      </label>
                      <label class={[
                        "flex items-center gap-2 p-3 rounded-lg cursor-pointer transition-all border flex-1 justify-center",
                        if(@pending_direction == "Both", 
                          do: "bg-green-600/20 border-green-500 text-white", 
                          else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                      ]}>
                        <input type="radio" name="direction" value="Both" 
                          checked={@pending_direction == "Both"}
                          phx-click="select_direction" phx-value-direction="Both" phx-target={@myself}
                          class="hidden" />
                        <span class="text-xl">↑↓</span>
                        <span class="text-sm font-medium">Both</span>
                      </label>
                    </div>
                  </div>
                <% end %>

                <!-- Color Selection -->
                <div class="mb-4">
                  <p class="text-white text-sm font-medium mb-2">Zone Color</p>
                  <div class="flex gap-2">
                    <%= for {color, name} <- @color_options do %>
                      <label class={[
                        "w-8 h-8 rounded-full cursor-pointer border-2 transition-all",
                        if(@pending_color == color, do: "border-white ring-2 ring-white/50", else: "border-transparent hover:border-white/50")
                      ]} style={"background-color: #{color_to_css(color)}"}>
                        <input 
                          type="radio" 
                          name="color_choice"
                          value={Jason.encode!(color)}
                          checked={@pending_color == color}
                          phx-click="select_color"
                          phx-value-color={Jason.encode!(color)}
                          phx-target={@myself}
                          class="hidden" 
                        />
                        <span class="sr-only"><%= name %></span>
                      </label>
                    <% end %>
                  </div>
                </div>

                <!-- Hidden fields and buttons -->
                <input type="hidden" name="coordinates" value={Jason.encode!(@pending_coordinates)} />
                <input type="hidden" name="type" value={@selected_type} />
                <input type="hidden" name="color" value={Jason.encode!(@pending_color)} />

                <div class="flex gap-2 justify-end">
                  <button type="button" phx-click="cancel_pending" phx-target={@myself}
                    class="px-4 py-2 bg-green-800 hover:bg-green-700 text-white rounded-lg text-sm font-medium transition-colors">
                    Cancel
                  </button>
                  <button type="submit"
                    class="px-6 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-bold transition-colors">
                    ✓ Save Zone
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <!-- Edit Zone/Line Form (below video) -->
          <%= if @editing_shape do %>
            <% {_shape_type, shape, _type} = @editing_shape %>
            <div class="bg-green-900/80 border border-green-500 rounded-lg p-4 mt-3">
              <div class="flex items-center gap-2 text-white text-sm font-medium mb-3">
                ✏️ Editing "<%= shape.name %>" - Drag corner points to adjust coordinates
              </div>
              
              <!-- Name Input -->
              <div class="mb-3">
                <label class="block text-white text-xs mb-1">Name</label>
                <input type="text" value={@edit_name} phx-blur="update_edit_name" phx-target={@myself}
                  class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none" />
              </div>
              
              <!-- Classes Selection (not for Object Guarding/Object Left Behind/Crowd Estimation) -->
              <%= if not match?({:zone, _, "object_removed"}, @editing_shape) and not match?({:zone, _, "object_left"}, @editing_shape) and not match?({:zone, _, "crowd_estimation"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Detection Classes</label>
                  <div class="flex flex-wrap gap-2">
                    <!-- Selectable classes -->
                    <%= for cls <- @selectable_classes do %>
                      <label class="flex items-center gap-1.5 cursor-pointer">
                        <input type="checkbox" 
                          checked={cls in (@edit_classes || [])} 
                          phx-click="toggle_edit_class" 
                          phx-value-class={cls}
                          phx-target={@myself}
                          class="rounded border-green-700 bg-black text-green-500 focus:ring-green-500" />
                        <span class="text-white text-sm"><%= cls %></span>
                      </label>
                    <% end %>
                    <!-- Readonly classes (Fire, LPD, Face) -->
                    <%= for cls <- @readonly_classes do %>
                      <label class="flex items-center gap-1.5 cursor-not-allowed opacity-50">
                        <input type="checkbox" 
                          checked={false}
                          disabled
                          class="rounded border-green-700 bg-green-800 text-white/70 cursor-not-allowed" />
                        <span class="text-white/80 text-sm"><%= cls %></span>
                      </label>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- Loitering/Object Guarding/Object Left Behind: Seconds field -->
              <%= if match?({:zone, _, "loitering"}, @editing_shape) or match?({:zone, _, "object_removed"}, @editing_shape) or match?({:zone, _, "object_left"}, @editing_shape) do %>
                <div class="mb-3">
                  <%= cond do %>
                    <% match?({:zone, _, "loitering"}, @editing_shape) -> %>
                      <label class="block text-white text-xs mb-1">Time threshold (seconds)</label>
                    <% match?({:zone, _, "object_removed"}, @editing_shape) -> %>
                      <label class="block text-white text-xs mb-1">Alarm if object is missing for more than (seconds)</label>
                    <% match?({:zone, _, "object_left"}, @editing_shape) -> %>
                      <label class="block text-white text-xs mb-1">Alarm if object is left behind for more than (seconds)</label>
                  <% end %>
                  <input type="number" 
                    value={@edit_seconds} 
                    min="1" max="3600"
                    phx-blur="update_edit_seconds" 
                    phx-target={@myself}
                    class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none" />
                </div>
              <% end %>

              <!-- Crowding: Object count and seconds -->
              <%= if match?({:zone, _, "crowding"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Maximum number of objects</label>
                  <input type="number" 
                    value={@edit_object_count} 
                    min="1" max="100"
                    phx-blur="update_edit_object_count" 
                    phx-target={@myself}
                    class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none" />
                </div>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Time threshold (seconds, 0 = immediate)</label>
                  <input type="number" 
                    value={@edit_seconds} 
                    min="0" max="3600"
                    phx-blur="update_edit_seconds" 
                    phx-target={@myself}
                    class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none" />
                </div>
              <% end %>
              <%= if match?({:zone, _, "crossing"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Trigger on</label>
                  <select 
                    phx-change="update_edit_area_event"
                    phx-target={@myself}
                    class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none">
                    <%= for {value, label} <- @area_event_options do %>
                      <option value={value} selected={@edit_area_event == value}><%= label %></option>
                    <% end %>
                  </select>
                </div>
                <div class="mb-3">
                  <label class="flex items-center gap-1.5 cursor-pointer">
                    <input 
                      type="checkbox" 
                      checked={@edit_ignore_stationary}
                      phx-click="toggle_edit_ignore_stationary"
                      phx-target={@myself}
                      class="rounded border-green-700 bg-black text-green-500 focus:ring-green-500" />
                    <span class="text-white text-sm">Ignore stationary objects</span>
                  </label>
                </div>
              <% end %>

              <!-- Tailgating: Seconds and Direction -->
              <%= if match?({:line, _, "tailgating"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Time threshold (seconds)</label>
                  <input type="number" 
                    value={@edit_seconds} 
                    min="1" max="60"
                    phx-blur="update_edit_seconds" 
                    phx-target={@myself}
                    class="w-full bg-black border border-green-700 rounded px-3 py-1.5 text-white text-sm focus:border-green-500 focus:outline-none" />
                </div>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Detection Direction</label>
                  <div class="flex gap-2">
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Up", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Up" 
                        checked={@edit_direction == "Up"}
                        phx-click="update_edit_direction" phx-value-direction="Up" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑</span>
                      <span class="text-xs">Up</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Down", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Down" 
                        checked={@edit_direction == "Down"}
                        phx-click="update_edit_direction" phx-value-direction="Down" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↓</span>
                      <span class="text-xs">Down</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Both", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Both" 
                        checked={@edit_direction == "Both"}
                        phx-click="update_edit_direction" phx-value-direction="Both" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑↓</span>
                      <span class="text-xs">Both</span>
                    </label>
                  </div>
                </div>
              <% end %>

              <!-- Line Crossing: Direction (Edit) -->
              <%= if match?({:line, _, "crossing"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Detection Direction</label>
                  <div class="flex gap-2">
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Up", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Up" 
                        checked={@edit_direction == "Up"}
                        phx-click="update_edit_direction" phx-value-direction="Up" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑</span>
                      <span class="text-xs">Up</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Down", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Down" 
                        checked={@edit_direction == "Down"}
                        phx-click="update_edit_direction" phx-value-direction="Down" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↓</span>
                      <span class="text-xs">Down</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Both", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Both" 
                        checked={@edit_direction == "Both"}
                        phx-click="update_edit_direction" phx-value-direction="Both" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑↓</span>
                      <span class="text-xs">Both</span>
                    </label>
                  </div>
                </div>
              <% end %>

              <!-- Line Counting: Direction (Edit) -->
              <%= if match?({:line, _, "counting"}, @editing_shape) do %>
                <div class="mb-3">
                  <label class="block text-white text-xs mb-1">Counting Direction</label>
                  <div class="flex gap-2">
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Up", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Up" 
                        checked={@edit_direction == "Up"}
                        phx-click="update_edit_direction" phx-value-direction="Up" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑</span>
                      <span class="text-xs">Up</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Down", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Down" 
                        checked={@edit_direction == "Down"}
                        phx-click="update_edit_direction" phx-value-direction="Down" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↓</span>
                      <span class="text-xs">Down</span>
                    </label>
                    <label class={[
                      "flex items-center gap-1 p-2 rounded cursor-pointer transition-all border flex-1 justify-center",
                      if(@edit_direction == "Both", 
                        do: "bg-green-600/20 border-green-500 text-white", 
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}>
                      <input type="radio" name="edit_direction" value="Both" 
                        checked={@edit_direction == "Both"}
                        phx-click="update_edit_direction" phx-value-direction="Both" phx-target={@myself}
                        class="hidden" />
                      <span class="text-lg">↑↓</span>
                      <span class="text-xs">Both</span>
                    </label>
                  </div>
                </div>
              <% end %>

              
              <!-- Action Buttons -->
              <div class="flex gap-2">
                <button phx-click="save_edit"
                  class="bg-green-600 hover:bg-green-700 text-white px-4 py-1.5 rounded text-sm font-medium">
                  ✓ Save Changes
                </button>
                <button phx-click="cancel_edit" phx-target={@myself}
                  class="bg-green-800 hover:bg-green-700 text-white px-4 py-1.5 rounded text-sm">
                  Cancel
                </button>
              </div>
            </div>
          <% end %>



          <!-- Recent Events (below video) -->
          <%= if @instance && @instance.status == "running" && @recent_events != [] do %>
            <div class="bg-black rounded-lg p-3 mt-3">
              <h4 class="text-white font-medium text-sm mb-2">Recent Events</h4>
              <div class="flex flex-wrap gap-2">
                <%= for event <- Enum.take(@recent_events, 5) do %>
                  <span class="px-2 py-1 bg-black rounded text-xs text-white">
                    <%= event.type %> - <%= Calendar.strftime(event.timestamp, "%H:%M:%S") %>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- RIGHT: Analytics Panel (fixed width 280px, dynamic height) -->
        <div class="w-72 flex-shrink-0" style="height: calc(100vh - 280px); min-height: 400px;">
          <div class="bg-black rounded-lg overflow-hidden h-full flex flex-col">
            <!-- Header -->
            <div class="px-4 py-3 border-b border-green-800">
              <h4 class="text-white font-semibold">Analytics</h4>
            </div>

            <!-- Analytics List with nested active rules - scrollable (fills remaining height) -->
            <div class="divide-y divide-green-800/50 overflow-y-auto flex-1">
              <%= for t <- @zone_types do %>
                <% active_rules = get_rules_for_type(t.id, @zones) %>
                <div>
                  <button
                    phx-click="select_and_draw"
                    phx-value-type={"zone:#{t.id}"}
                    phx-target={@myself}
                    disabled={@instance == nil}
                    class={"w-full px-4 py-2.5 text-left hover:bg-black/50 transition-colors #{if @selected_type == "zone:#{t.id}", do: "bg-black border-l-2 border-yellow-500", else: ""} disabled:opacity-50 disabled:cursor-not-allowed"}
                  >
                    <div class="flex items-center justify-between">
                      <span class="text-white text-sm"><%= t.name %></span>
                      <%= if active_rules != [] do %>
                        <span class="text-xs px-1.5 py-0.5 bg-green-600 text-white rounded-full"><%= length(active_rules) %></span>
                      <% end %>
                    </div>
                  </button>
                  <!-- Nested active rules for this type -->
                  <%= if active_rules != [] do %>
                    <div class="bg-black/50 border-l-2 border-green-700 ml-4">
                      <%= for zone <- active_rules do %>
                        <% is_viewing_zone = @viewing_shape != nil and match?({:zone, _}, @viewing_shape) and elem(@viewing_shape, 1).area_id == zone.area_id %>
                        <div class={"flex justify-between items-center text-sm py-1.5 px-3 hover:bg-black/30 #{if is_viewing_zone, do: "bg-green-900/50 border-l-2 border-green-400", else: ""}"}>
                          <button phx-click="view_zone" phx-value-id={zone.area_id} phx-target={@myself}
                            class="text-white text-xs hover:text-white flex-grow text-left">
                            <%= zone.name %>
                            <%= if zone.classes != [] do %>
                              <span class="text-white/60 ml-1">(<%= Enum.join(zone.classes, ", ") %>)</span>
                            <% end %>
                          </button>
                          <div class="flex gap-1">
                            <button phx-click="view_zone" phx-value-id={zone.area_id} phx-target={@myself}
                              class="text-green-400 hover:text-green-300 text-xs" title="View">👁</button>
                            <button phx-click="edit_zone" phx-value-id={zone.area_id} phx-value-type={t.id} phx-target={@myself}
                              class="text-green-400 hover:text-green-300 text-xs" title="Edit">✎</button>
                            <button phx-click="delete_zone" phx-value-id={zone.area_id} phx-target={@myself}
                              class="text-red-400 hover:text-red-300 text-xs">✕</button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= for t <- @line_types do %>
                <% active_lines = get_lines_for_type(t.id, @lines) %>
                <div>
                  <button
                    phx-click="select_and_draw"
                    phx-value-type={"line:#{t.id}"}
                    phx-target={@myself}
                    disabled={@instance == nil}
                    class={"w-full px-4 py-2.5 text-left hover:bg-black/50 transition-colors #{if @selected_type == "line:#{t.id}", do: "bg-black border-l-2 border-yellow-500", else: ""} disabled:opacity-50 disabled:cursor-not-allowed"}
                  >
                    <div class="flex items-center justify-between">
                      <span class="text-white text-sm"><%= t.name %></span>
                      <%= if active_lines != [] do %>
                        <span class="text-xs px-1.5 py-0.5 bg-green-600 text-white rounded-full"><%= length(active_lines) %></span>
                      <% end %>
                    </div>
                  </button>
                  <!-- Nested active lines for this type -->
                  <%= if active_lines != [] do %>
                    <div class="bg-black/50 border-l-2 border-green-700 ml-4">
                      <%= for line <- active_lines do %>
                        <% is_viewing_line = @viewing_shape != nil and match?({:line, _}, @viewing_shape) and elem(@viewing_shape, 1).line_id == line.line_id %>
                        <div class={"flex justify-between items-center text-sm py-1.5 px-3 hover:bg-black/30 #{if is_viewing_line, do: "bg-green-900/50 border-l-2 border-green-400", else: ""}"}>
                          <button phx-click="view_line" phx-value-id={line.line_id} phx-target={@myself}
                            class="text-white text-xs hover:text-white flex-grow text-left">
                            <%= line.name %>
                            <%= if line.classes != [] do %>
                              <span class="text-white/60 ml-1">(<%= Enum.join(line.classes, ", ") %>)</span>
                            <% end %>
                          </button>
                          <div class="flex gap-1">
                            <button phx-click="view_line" phx-value-id={line.line_id} phx-target={@myself}
                              class="text-green-400 hover:text-green-300 text-xs" title="View">👁</button>
                            <button phx-click="edit_line" phx-value-id={line.line_id} phx-value-type={t.id} phx-target={@myself}
                              class="text-green-400 hover:text-green-300 text-xs" title="Edit">✎</button>
                            <button phx-click="delete_line" phx-value-id={line.line_id} phx-target={@myself}
                              class="text-red-400 hover:text-red-300 text-xs">✕</button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Settings Panel (shown when toggle_settings is active) -->
      <%= if @show_settings && @instance do %>
        <div class="bg-black rounded-lg p-4 mt-4">
          <h4 class="text-white font-semibold mb-4">Instance Configuration</h4>
          <.form for={%{}} phx-submit="save_config" phx-target={@myself}>
            <div class="grid grid-cols-2 gap-4">
              <!-- Detector Mode -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Detector Mode</label>
                <select name="detector_mode" 
                  class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm">
                  <option value="SmartDetection" selected={@instance.detector_mode == "SmartDetection"}>Smart Detection</option>
                  <option value="FullFrame" selected={@instance.detector_mode == "FullFrame"}>Full Frame</option>
                </select>
              </div>

              <!-- Frame Rate Limit -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Frame Rate Limit</label>
                <input type="number" name="frame_rate_limit" min="1" max="30"
                  value={@instance.frame_rate_limit}
                  class="w-full bg-black border border-green-700 text-white rounded-lg px-3 py-2 text-sm" />
              </div>

              <!-- Detection Sensitivity -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Detection Sensitivity</label>
                <div class="flex gap-2">
                  <%= for level <- ["Low", "Medium", "High"] do %>
                    <label class={[
                      "flex-1 text-center py-2 rounded cursor-pointer text-sm transition-all",
                      if(@instance.detection_sensitivity == level,
                        do: "bg-green-600 text-white",
                        else: "bg-black text-white/80 hover:bg-green-800")
                    ]}>
                      <input type="radio" name="detection_sensitivity" value={level}
                        checked={@instance.detection_sensitivity == level} class="hidden" />
                      <%= level %>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Movement Sensitivity -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Movement Sensitivity</label>
                <div class="flex gap-2">
                  <%= for level <- ["Low", "Medium", "High"] do %>
                    <label class={[
                      "flex-1 text-center py-2 rounded cursor-pointer text-sm transition-all",
                      if(@instance.movement_sensitivity == level,
                        do: "bg-green-600 text-white",
                        else: "bg-black text-white/80 hover:bg-green-800")
                    ]}>
                      <input type="radio" name="movement_sensitivity" value={level}
                        checked={@instance.movement_sensitivity == level} class="hidden" />
                      <%= level %>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Attributes Extraction -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Attributes Extraction</label>
                <p class="text-white/60 text-xs mb-2">Extract attributes from detected objects</p>
                <div class="flex gap-2">
                  <%= for mode <- ["None", "Person", "Vehicle", "Both"] do %>
                    <label class={[
                      "flex-1 text-center py-2 rounded cursor-pointer text-sm transition-all",
                      if(@attributes_extraction_mode == mode,
                        do: "bg-green-600 text-white",
                        else: "bg-black text-white/80 hover:bg-green-800")
                    ]}
                    phx-click="select_attributes_mode" phx-value-mode={mode} phx-target={@myself}>
                      <input type="radio" name="attributes_extraction" value={mode}
                        checked={@attributes_extraction_mode == mode} class="hidden" />
                      <%= mode %>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Feature Extraction -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Feature Extraction</label>
                <p class="text-white/60 text-xs mb-2">Enable feature extraction for recognition</p>
                <div class="flex gap-2">
                  <%= for type <- ["Person", "Vehicle", "Face"] do %>
                    <label class={[
                      "flex items-center gap-2 px-3 py-2 rounded cursor-pointer text-sm transition-all border",
                      if(type in @feature_extraction_types,
                        do: "bg-green-600/20 border-green-500 text-white",
                        else: "bg-black border-green-700 text-white/80 hover:border-green-500")
                    ]}
                    phx-click="toggle_feature_type" phx-value-type={type} phx-target={@myself}>
                      <input type="checkbox" name="feature_extraction[]" value={type}
                        checked={type in @feature_extraction_types}
                        class="w-4 h-4 rounded bg-black border-green-700 text-green-500 focus:ring-green-500 pointer-events-none" />
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Face Detection -->
              <div>
                <label class="text-white text-sm font-medium block mb-2">Face Detection</label>
                <p class="text-white/60 text-xs mb-2">Enable face detection for analytics</p>
                <div class="flex items-center gap-3">
                  <button type="button" 
                    phx-click="toggle_face_detection" 
                    phx-target={@myself}
                    class={[
                      "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 focus:ring-offset-black",
                      if(@face_detection_enabled, do: "bg-green-600", else: "bg-green-700")
                    ]}>
                    <span class={[
                      "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                      if(@face_detection_enabled, do: "translate-x-5", else: "translate-x-0")
                    ]}></span>
                  </button>
                  <span class="text-sm text-white/80"><%= if @face_detection_enabled, do: "Enabled", else: "Disabled" %></span>
                </div>
              </div>
            </div>

            <!-- Analytics Summary -->
            <div class="mt-4 p-3 bg-black/50 rounded-lg">
              <div class="flex justify-between text-sm">
                <span class="text-white/80">Zones configured:</span>
                <span class="text-white font-medium"><%= length(@zones) %></span>
              </div>
              <div class="flex justify-between text-sm mt-1">
                <span class="text-white/80">Lines configured:</span>
                <span class="text-white font-medium"><%= length(@lines) %></span>
              </div>
            </div>

            <div class="flex gap-2 justify-end mt-4">
              <button type="button" phx-click="toggle_settings" phx-target={@myself}
                class="px-4 py-2 bg-green-800 hover:bg-green-700 text-white rounded-lg text-sm">
                Cancel
              </button>
              <button type="submit"
                class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium">
                Save Configuration
              </button>
            </div>
          </.form>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       cvedix_status: :unknown,
       instance: nil,
       zones: [],
       lines: [],
       zone_types: @zone_types,
       line_types: @line_types,
       object_classes: @object_classes,
       selectable_classes: @selectable_classes,
       readonly_classes: @readonly_classes,
       selected_classes: ["Person", "Vehicle"],
       selected_type: nil,
       selected_type_info: nil,
       drawing_mode: nil,
       pending_coordinates: nil,
       pending_name: "",
       pending_seconds: 120,
       pending_direction: "Both",  # For tailgating line: "Up", "Down", "Both"
       pending_area_event: "Both",  # For crossing: "Enter", "Exit", "Both"
       pending_ignore_stationary: true,  # For crossing: ignore stationary objects
       pending_color: [1, 0, 0, 1],
       color_options: [
         {[1, 0, 0, 1], "Red"},
         {[0, 1, 0, 1], "Green"},
         {[0, 0, 1, 1], "Blue"},
         {[1, 1, 0, 1], "Yellow"},
         {[1, 0, 1, 1], "Magenta"},
         {[0, 1, 1, 1], "Cyan"}
       ],
       area_event_options: [
         {"Enter", "Only when an entity enters inside the area"},
         {"Exit", "Only when an entity exits outside the area"},
         {"Both", "When an entity enters or exits the area"}
       ],
       recent_events: [],
       cvedix_frame: nil,
       frame_timer: nil,
       show_settings: false,
       viewing_shape: nil,  # Track which zone/line is being viewed {:zone, zone} or {:line, line}
       editing_shape: nil,  # Track which shape is being edited {:zone, zone, type} or {:line, line, type}
       edit_name: nil,      # Edited name during edit mode
       edit_classes: nil,   # Edited classes during edit mode
       edit_seconds: 120,   # Edited seconds for loitering
       edit_object_count: 5, # Edited object count for crowding
       edit_direction: "Both",  # Edited direction for tailgating
       edit_area_event: "Both",  # Edited area event for crossing
       edit_ignore_stationary: true,  # Edited ignore stationary for crossing
       attributes_extraction_mode: "None",  # Attributes extraction mode: None, Person, Vehicle, Both
       feature_extraction_types: ["Person", "Vehicle", "Face"],  # Feature extraction types
       face_detection_enabled: false  # Face detection enabled/disabled
     )}
  end

  # Handle save_edited_coordinates forwarded from parent LiveView via send_update
  # NOTE: This MUST be before the device pattern to ensure proper matching
  @impl true
  def update(%{save_edited_coordinates: params}, socket) do
    Logger.info("[AnalyticsTab] save_edited_coordinates via update: #{inspect(params)}")
    
    coords = params["coordinates"]
    normalized_coords = Enum.map(coords, fn c -> 
      %{x: c["x"] || c[:x], y: c["y"] || c[:y]} 
    end)
    
    # Call the actual save logic but convert {:noreply, socket} to {:ok, socket}
    case do_save_edited_coordinates(socket, normalized_coords) do
      {:noreply, updated_socket} -> {:ok, updated_socket}
      other -> other
    end
  end

  # Handle drawing_complete forwarded from parent LiveView via send_update
  @impl true
  def update(%{drawing_complete: params}, socket) do
    coords = params["coordinates"]
    
    Logger.info("[AnalyticsTab] Drawing complete via update! Coords: #{inspect(coords)}")
    
    normalized_coords = Enum.map(coords, fn c ->
      x = c["x"] || c[:x] || 0
      y = c["y"] || c[:y] || 0
      %{x: x, y: y}
    end)

    Logger.info("[AnalyticsTab] Setting pending_coordinates: #{inspect(normalized_coords)}")

    mode = if String.starts_with?(socket.assigns.selected_type || "", "zone:"), do: "zone", else: "line"

    {:ok,
     socket
     |> assign(drawing_mode: nil, pending_coordinates: normalized_coords)
     |> push_event("load_pending", %{coordinates: normalized_coords, mode: mode})}
  end

  @impl true
  def update(%{device: device} = assigns, socket) do
    socket = assign(socket, assigns)

    # Check CVEDIX connection
    cvedix_status =
      case CVEDIX.health_check() do
        {:ok, _} -> :connected
        _ -> :disconnected
      end

    # Load instance and analytics
    {instance, zones, lines} = load_analytics(device.id)

    # Fetch saved settings from API if instance exists
    {attributes_mode, feature_types} = if instance do
      fetch_extraction_settings(instance.instance_id)
    else
      {"None", []}
    end

    # Sync face detection state from device settings
    face_detection_enabled = case device.settings do
      %{enable_face_detection: true} -> true
      _ -> false
    end

    # Don't auto-fetch frames - only fetch when user selects an analytics type

    # Preserve editing state if already set (to prevent losing metadata during parent re-renders)
    editing_shape = Map.get(socket.assigns, :editing_shape, nil)
    edit_name = Map.get(socket.assigns, :edit_name, nil)
    edit_classes = Map.get(socket.assigns, :edit_classes, nil)
    
    socket = assign(socket,
      cvedix_status: cvedix_status,
      instance: instance,
      zones: zones,
      lines: lines,
      viewing_shape: nil,
      editing_shape: editing_shape,
      edit_name: edit_name,
      edit_classes: edit_classes,
      attributes_extraction_mode: attributes_mode,
      feature_extraction_types: feature_types,
      face_detection_enabled: face_detection_enabled
    )

    # Don't auto-load shapes - user must click to view specific zone/line

    {:ok, socket}
  end

  defp fetch_extraction_settings(instance_id) do
    # Fetch attributes extraction mode
    attributes_mode = case CVEDIX.Client.get("/v1/securt/instance/#{instance_id}/attributes_extraction") do
      {:ok, mode} when is_binary(mode) -> mode
      _ -> "None"
    end

    # Fetch feature extraction types
    feature_types = case CVEDIX.Client.get("/v1/securt/instance/#{instance_id}/feature_extraction") do
      {:ok, %{"types" => types}} when is_list(types) -> types
      _ -> []
    end

    {attributes_mode, feature_types}
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("create_instance", _params, socket) do
    device = socket.assigns.device

    case CVEDIX.setup_intrusion_detection(device.id, name: device.name) do
      {:ok, instance} ->
        {:noreply,
         socket
         |> assign(instance: instance)
         |> put_flash(:info, "Analytics enabled for #{device.name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_instance", _params, socket) do
    instance = socket.assigns.instance

    with :ok <- CVEDIX.Instance.load(instance.instance_id),
         :ok <- CVEDIX.Instance.start(instance.instance_id) do
      {:noreply, assign(socket, instance: %{instance | status: "running"})}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_instance", _params, socket) do
    case CVEDIX.Instance.stop(socket.assigns.instance.instance_id) do
      :ok ->
        instance = %{socket.assigns.instance | status: "stopped"}
        {:noreply, assign(socket, instance: instance)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("remove_instance", _params, socket) do
    case CVEDIX.stop_intrusion_detection(socket.assigns.device.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(instance: nil, zones: [], lines: [], show_settings: false)
         |> push_event("clear_shapes", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    {:noreply, assign(socket, show_settings: !socket.assigns.show_settings)}
  end

  @impl true
  def handle_event("select_attributes_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, attributes_extraction_mode: mode)}
  end

  @impl true
  def handle_event("toggle_feature_type", %{"type" => type}, socket) do
    current_types = socket.assigns.feature_extraction_types
    new_types = if type in current_types do
      List.delete(current_types, type)
    else
      [type | current_types]
    end
    {:noreply, assign(socket, feature_extraction_types: new_types)}
  end

  @impl true
  def handle_event("toggle_face_detection", _params, socket) do
    new_value = !socket.assigns.face_detection_enabled
    instance = socket.assigns.instance
    device = socket.assigns.device
    
    # 1. Persist face detection state to device settings (DB)
    case Devices.update_device_settings(device, %{enable_face_detection: new_value}) do
      {:ok, updated_device} ->
        # 2. Set API flag on CVEDIX-RT
        if instance do
          set_face_detection(instance.instance_id, new_value)
          
          # 3. Restart pipeline to rebuild with/without face_detector node
          Task.start(fn ->
            Logger.info("[AnalyticsTab] Restarting instance #{instance.instance_id} for face detection toggle (enabled=#{new_value})")
            CVEDIX.Instance.restart(instance.instance_id)
          end)
        end
        
        {:noreply,
         socket
         |> assign(face_detection_enabled: new_value, device: updated_device)
         |> put_flash(:info, if(new_value, do: "Face detection enabled — pipeline restarting...", else: "Face detection disabled — pipeline restarting..."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update face detection settings")}
    end
  end

  @impl true
  def handle_event("save_config", params, socket) do
    device_id = socket.assigns.device.id
    instance = socket.assigns.instance
    
    config_params = %{
      detector_mode: params["detector_mode"],
      detection_sensitivity: params["detection_sensitivity"],
      movement_sensitivity: params["movement_sensitivity"],
      frame_rate_limit: String.to_integer(params["frame_rate_limit"] || "10")
    }

    # Get attributes extraction mode
    attributes_mode = params["attributes_extraction"] || "None"
    
    # Get feature extraction types (checkboxes)
    feature_types = params["feature_extraction"] || []
    feature_types = if is_list(feature_types), do: feature_types, else: [feature_types]
    
    # Update instance config
    result = case CVEDIX.update_instance_config(device_id, config_params) do
      {:ok, updated_instance} -> {:ok, updated_instance}
      {:error, reason} -> {:error, reason}
    end

    # Set attributes extraction mode and feature extraction types via API
    if instance do
      # Only call API if mode is not None
      if attributes_mode != "None" do
        set_attributes_extraction(instance.instance_id, attributes_mode)
      end
      set_feature_extraction(instance.instance_id, feature_types)
    end
    
    case result do
      {:ok, updated_instance} ->
        {:noreply,
         socket
         |> assign(
           instance: updated_instance, 
           show_settings: false, 
           attributes_extraction_mode: attributes_mode,
           feature_extraction_types: feature_types
         )
         |> put_flash(:info, "Configuration saved successfully")}
        
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("select_analytics_type", %{"_target" => _, "value" => ""}, socket) do
    {:noreply, assign(socket, selected_type: nil, selected_type_info: nil)}
  end

  def handle_event("select_analytics_type", %{"value" => type}, socket) do
    type_info = find_type_info(type)
    default_name = if type_info, do: "#{type_info.name} #{length(socket.assigns.zones) + length(socket.assigns.lines) + 1}", else: ""

    {:noreply,
     assign(socket,
       selected_type: type,
       selected_type_info: type_info,
       pending_name: default_name
     )}
  end

  @impl true
  def handle_event("start_drawing", _params, socket) do
    mode = if String.starts_with?(socket.assigns.selected_type || "", "zone:"), do: "zone", else: "line"

    {:noreply,
     socket
     |> assign(drawing_mode: mode)
     |> push_event("start_drawing", %{mode: mode})}
  end

  @impl true
  def handle_event("finish_drawing", _params, socket) do
    # Push event to JavaScript to get coordinates and finish
    {:noreply, push_event(socket, "finish_drawing", %{})}
  end

  @impl true
  def handle_event("cancel_drawing", _params, socket) do
    {:noreply,
     socket
     |> assign(drawing_mode: nil, pending_coordinates: nil)
     |> push_event("cancel_drawing", %{})}
  end

  @impl true
  def handle_event("drawing_complete", %{"mode" => _mode, "coordinates" => coords}, socket) do
    Logger.info("[AnalyticsTab] Drawing complete! Coords: #{inspect(coords)}")

    try do
      # Convert coordinates - handle both string and atom keys
      normalized_coords = Enum.map(coords, fn c ->
        x = c["x"] || c[:x] || 0
        y = c["y"] || c[:y] || 0
        %{x: x, y: y}
      end)

      Logger.info("[AnalyticsTab] Setting pending_coordinates: #{inspect(normalized_coords)}")

      mode = if String.starts_with?(socket.assigns.selected_type || "", "zone:"), do: "zone", else: "line"

      {:noreply,
       socket
       |> assign(drawing_mode: nil, pending_coordinates: normalized_coords)
       |> push_event("load_pending", %{coordinates: normalized_coords, mode: mode})}
    rescue
      e ->
        Logger.error("[AnalyticsTab] Error processing coordinates: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "Failed to process drawing")}
    end
  end

  @impl true
  def handle_event("cancel_pending", _params, socket) do
    {:noreply,
     socket
     |> assign(pending_coordinates: nil, selected_type: nil, selected_type_info: nil)
     |> push_event("clear_pending", %{})
     |> push_event("cancel_drawing", %{})}
  end

  @impl true
  def handle_event("select_and_draw", %{"type" => type}, socket) do
    type_info = find_type_info(type)
    default_name = if type_info, do: "#{type_info.name} #{length(socket.assigns.zones) + length(socket.assigns.lines) + 1}", else: ""
    mode = if String.starts_with?(type, "zone:"), do: "zone", else: "line"

    Logger.info("[AnalyticsTab] select_and_draw: type=#{type}, mode=#{mode}")

    # Clear any existing preview and start fresh drawing mode
    {:noreply,
     socket
     |> assign(selected_type: type, selected_type_info: type_info, pending_name: default_name, drawing_mode: mode)
     |> assign(viewing_shape: nil, editing_shape: nil)
     |> push_event("clear_shapes", %{})
     |> push_event("start_drawing", %{mode: mode})}
  end

  @impl true
  def handle_event("save_analytics", params, socket) do
    instance = socket.assigns.instance
    type = params["type"]
    coords = Jason.decode!(params["coordinates"])

    # Build params - use selected_classes from socket
    selected_classes = socket.assigns.selected_classes
    classes = if selected_classes == [], do: ["Person"], else: selected_classes

    # Get selected color from params (or use pending_color from socket)
    selected_color = case params["color"] do
      nil -> socket.assigns.pending_color
      color_json -> Jason.decode!(color_json)
    end

    analytics_params = %{
      name: params["name"],
      coordinates: Enum.map(coords, fn c -> %{x: c["x"], y: c["y"]} end),
      classes: classes,
      color: selected_color
    }

    # Add extra params based on type
    analytics_params =
      analytics_params
      |> maybe_add_seconds(params)
      |> maybe_add_count(params)
      |> maybe_add_direction(params)
      |> maybe_add_crossing_params(type, socket)
      |> maybe_add_tailgating_params(type, socket)

    result =
      if String.starts_with?(type, "zone:") do
        zone_type = String.replace(type, "zone:", "")
        Analytics.create_area(instance.instance_id, zone_type, analytics_params)
      else
        line_type = String.replace(type, "line:", "")
        Analytics.create_line(instance.instance_id, line_type, analytics_params)
      end

    case result do
      {:ok, _} ->
        # Reload analytics
        {_, zones, lines} = load_analytics(socket.assigns.device.id)

        {:noreply,
         socket
         |> assign(zones: zones, lines: lines, pending_coordinates: nil, selected_type: nil, selected_type_info: nil)
         |> push_event("load_shapes", %{zones: zones, lines: lines})
         |> push_event("clear_pending", %{})
         |> put_flash(:info, "Analytics saved")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("view_zone", %{"id" => area_id}, socket) do
    zone = Enum.find(socket.assigns.zones, &(&1.area_id == area_id))
    
    if zone do
      {:noreply,
       socket
       |> assign(viewing_shape: {:zone, zone})
       |> push_event("clear_shapes", %{})
       |> push_event("load_shapes", %{zones: [zone], lines: []})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_line", %{"id" => line_id}, socket) do
    line = Enum.find(socket.assigns.lines, &(&1.line_id == line_id))
    
    if line do
      {:noreply,
       socket
       |> assign(viewing_shape: {:line, line})
       |> push_event("clear_shapes", %{})
       |> push_event("load_shapes", %{zones: [], lines: [line]})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_view", _params, socket) do
    {:noreply,
     socket
     |> assign(viewing_shape: nil)
     |> push_event("clear_shapes", %{})}
  end

  @impl true
  def handle_event("edit_zone", %{"id" => area_id, "type" => zone_type}, socket) do
    zone = Enum.find(socket.assigns.zones, &(&1.area_id == area_id))
    
    if zone do
      Logger.info("[AnalyticsTab] Starting edit mode for zone: #{zone.name}")
      {:noreply,
       socket
       |> assign(viewing_shape: {:zone, zone}, editing_shape: {:zone, zone, zone_type})
       |> assign(edit_name: zone.name, edit_classes: zone.classes || ["Person"])
       |> assign(edit_seconds: Map.get(zone, :seconds, 120))
       |> assign(edit_object_count: Map.get(zone, :object_count, 5))
       |> assign(edit_area_event: Map.get(zone, :area_event, "Both"))
       |> assign(edit_ignore_stationary: Map.get(zone, :ignore_stationary_object, true))
       |> push_event("clear_shapes", %{})
       |> push_event("load_shapes", %{zones: [zone], lines: []})
       |> push_event("start_edit", %{shapeIndex: 0})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_line", %{"id" => line_id, "type" => line_type}, socket) do
    line = Enum.find(socket.assigns.lines, &(&1.line_id == line_id))
    
    if line do
      Logger.info("[AnalyticsTab] Starting edit mode for line: #{line.name}")
      {:noreply,
       socket
       |> assign(viewing_shape: {:line, line}, editing_shape: {:line, line, line_type})
       |> assign(edit_name: line.name, edit_classes: line.classes || ["Person"])
       |> assign(edit_seconds: Map.get(line, :seconds, 4))
       |> assign(edit_direction: Map.get(line, :direction, "Both"))
       |> push_event("clear_shapes", %{})
       |> push_event("load_shapes", %{zones: [], lines: [line]})
       |> push_event("start_edit", %{shapeIndex: 0})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_edit", _params, socket) do
    # Trigger JS to push save_edited_coordinates with current coordinates
    {:noreply, push_event(socket, "trigger_save_edit", %{})}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(editing_shape: nil, edit_name: nil, edit_classes: nil)
     |> push_event("cancel_edit", %{})}
  end

  @impl true
  def handle_event("update_edit_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, edit_name: name)}
  end

  @impl true
  def handle_event("toggle_edit_class", %{"class" => class}, socket) do
    current_classes = socket.assigns.edit_classes || []
    
    updated_classes = 
      if class in current_classes do
        List.delete(current_classes, class)
      else
        [class | current_classes]
      end
    
    {:noreply, assign(socket, edit_classes: updated_classes)}
  end

  @impl true
  def handle_event("update_edit_seconds", %{"value" => seconds_str}, socket) do
    seconds = String.to_integer(seconds_str)
    {:noreply, assign(socket, edit_seconds: seconds)}
  end

  @impl true
  def handle_event("update_edit_object_count", %{"value" => count_str}, socket) do
    count = String.to_integer(count_str)
    {:noreply, assign(socket, edit_object_count: count)}
  end

  @impl true
  def handle_event("update_edit_area_event", %{"value" => event}, socket) do
    {:noreply, assign(socket, edit_area_event: event)}
  end

  @impl true
  def handle_event("toggle_edit_ignore_stationary", _params, socket) do
    current = socket.assigns.edit_ignore_stationary
    {:noreply, assign(socket, edit_ignore_stationary: !current)}
  end

  @impl true
  def handle_event("update_edit_direction", %{"direction" => direction}, socket) do
    {:noreply, assign(socket, edit_direction: direction)}
  end

  @impl true
  def handle_event("save_edited_coordinates", %{"type" => type, "name" => name, "coordinates" => coords}, socket) do
    Logger.info("[AnalyticsTab] save_edited_coordinates: type=#{type}, name=#{name}, coords_count=#{length(coords)}")
    
    # Defensive checks
    if is_nil(socket.assigns[:instance]) do
      Logger.error("[AnalyticsTab] No instance available!")
      {:noreply, put_flash(socket, :error, "No instance available")}
    else
      if is_nil(socket.assigns[:editing_shape]) do
        Logger.error("[AnalyticsTab] No editing_shape available!")
        {:noreply, put_flash(socket, :error, "No shape being edited")}
      else
        do_save_edited_coordinates(socket, coords)
      end
    end
  end

  @impl true
  def handle_event("delete_zone", %{"id" => area_id}, socket) do
    case Analytics.delete_area(socket.assigns.instance.instance_id, area_id) do
      :ok ->
        zones = Enum.reject(socket.assigns.zones, &(&1.area_id == area_id))
        {:noreply,
         socket
         |> assign(zones: zones, viewing_shape: nil)
         |> push_event("clear_shapes", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_line", %{"id" => line_id}, socket) do
    case Analytics.delete_line(socket.assigns.instance.instance_id, line_id) do
      :ok ->
        lines = Enum.reject(socket.assigns.lines, &(&1.line_id == line_id))
        {:noreply,
         socket
         |> assign(lines: lines, viewing_shape: nil)
         |> push_event("clear_shapes", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_class", %{"class" => class}, socket) do
    selected_classes = socket.assigns.selected_classes

    updated_classes =
      if class in selected_classes do
        List.delete(selected_classes, class)
      else
        [class | selected_classes]
      end

    {:noreply, assign(socket, selected_classes: updated_classes)}
  end

  @impl true
  def handle_event("select_color", %{"color" => color_json}, socket) do
    color = Jason.decode!(color_json)
    {:noreply, assign(socket, pending_color: color)}
  end

  @impl true
  def handle_event("select_area_event", %{"area_event" => event}, socket) do
    {:noreply, assign(socket, pending_area_event: event)}
  end

  @impl true
  def handle_event("select_direction", %{"direction" => direction}, socket) do
    {:noreply, assign(socket, pending_direction: direction)}
  end

  @impl true
  def handle_event("toggle_ignore_stationary", _params, socket) do
    current = socket.assigns.pending_ignore_stationary
    {:noreply, assign(socket, pending_ignore_stationary: !current)}
  end
  
  defp do_save_edited_coordinates(socket, coords) do
    instance_id = socket.assigns.instance.instance_id
    normalized_coords = Enum.map(coords, fn c -> 
      %{x: c["x"] || c[:x], y: c["y"] || c[:y]} 
    end)
    
    # Get user-edited name and classes from assigns (if modified)
    edit_name = socket.assigns[:edit_name]
    edit_classes = socket.assigns[:edit_classes]
    
    result = case socket.assigns.editing_shape do
      {:zone, zone, zone_type} ->
        # Map zone_type to CVEDIX Area type (required for PUT)
        cvedix_type = case zone_type do
          "intrusion" -> "AreaIntrusion"
          "crossing" -> "AreaCrossing"
          "loitering" -> "AreaLoitering"
          "crowding" -> "AreaCrowding"
          "occupancy" -> "AreaOccupancy"
          "crowd_estimation" -> "AreaCrowdEstimation"
          "dwelling" -> "AreaDwelling"
          "armed_person" -> "AreaArmedPerson"
          "fallen_person" -> "AreaFallenPerson"
          "object_left" -> "AreaObjectLeft"
          "object_removed" -> "AreaObjectRemoved"
          _ -> "Area#{String.capitalize(zone_type)}"
        end
        
        # Build params for PUT update - type is REQUIRED in body for CVEDIX API
        params = %{
          type: cvedix_type,
          name: edit_name || zone.name,
          coordinates: normalized_coords,
          classes: edit_classes || zone.classes || ["Person"],
          color: normalize_color_to_api(zone.color)
        }
        # Add type-specific fields
        edit_seconds = socket.assigns[:edit_seconds]
        edit_area_event = socket.assigns[:edit_area_event]
        edit_ignore_stationary = socket.assigns[:edit_ignore_stationary]
        params = case zone_type do
          "loitering" -> Map.put(params, :seconds, edit_seconds || zone[:seconds] || 120)
          "crossing" -> 
            params 
            |> Map.put(:areaEvent, edit_area_event || zone[:area_event] || "Both")
            |> Map.put(:ignoreStationaryObject, edit_ignore_stationary)
          "crowding" -> 
            edit_object_count = socket.assigns[:edit_object_count]
            params 
            |> Map.put(:objectCount, edit_object_count || zone[:object_count] || 5) 
            |> Map.put(:seconds, edit_seconds || zone[:seconds] || 0)
          "dwelling" -> Map.put(params, :seconds, zone[:seconds] || 60)
          "object_left" -> Map.put(params, :seconds, zone[:seconds] || 30)
          "object_removed" -> Map.put(params, :seconds, zone[:seconds] || 4)
          _ -> params
        end
        
        Logger.info("[AnalyticsTab] Updating zone via PUT: /area/#{zone_type}/#{zone.area_id}")
        Logger.info("[AnalyticsTab] PUT params: #{inspect(params)}")
        Analytics.update_area(instance_id, zone_type, zone.area_id, params)
        
      {:line, line, line_type} ->
        # Map line_type to CVEDIX Line type (required for PUT)
        cvedix_type = case line_type do
          "crossing" -> "LineCrossing"
          "counting" -> "LineCounting"
          "tailgating" -> "LineTailgating"
          _ -> "Line#{String.capitalize(line_type)}"
        end
        
        # Build params for PUT update - type is REQUIRED in body for CVEDIX API
        params = %{
          type: cvedix_type,
          name: edit_name || line.name,
          coordinates: normalized_coords,
          classes: edit_classes || line.classes || ["Person"],
          color: normalize_color_to_api(line.color)
        }
        # Add type-specific fields
        edit_seconds = socket.assigns[:edit_seconds]
        edit_direction = socket.assigns[:edit_direction]
        params = case line_type do
          "counting" -> Map.put(params, :direction, line[:direction] || "Both")
          "tailgating" -> 
            params 
            |> Map.put(:seconds, edit_seconds || line[:seconds] || 4)
            |> Map.put(:direction, edit_direction || line[:direction] || "Both")
          "crossing" ->
            Map.put(params, :direction, edit_direction || line[:direction] || "Both")
          _ -> params
        end
        
        Logger.info("[AnalyticsTab] Updating line via PUT: /line/#{line_type}/#{line.line_id}, params: #{inspect(params)}")
        Analytics.update_line(instance_id, line_type, line.line_id, params)
        
      _ ->
        {:error, :no_editing_shape}
    end
    
    case result do
      {:ok, _} ->
        # Reload analytics and push to canvas
        {_, zones, lines} = load_analytics(socket.assigns.device.id)
        {:noreply,
         socket
         |> assign(zones: zones, lines: lines, editing_shape: nil, viewing_shape: nil)
         |> push_event("cancel_edit", %{})
         |> push_event("load_shapes", %{zones: zones, lines: lines})
         |> put_flash(:info, "Updated successfully")}
         
      :ok ->
        # Some APIs return :ok instead of {:ok, _}
        {_, zones, lines} = load_analytics(socket.assigns.device.id)
        {:noreply,
         socket
         |> assign(zones: zones, lines: lines, editing_shape: nil, viewing_shape: nil)
         |> push_event("cancel_edit", %{})
         |> push_event("load_shapes", %{zones: zones, lines: lines})
         |> put_flash(:info, "Updated successfully")}
         
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
    end
  end

  # Handle PubSub events
  def handle_info({:cvedix_event, event}, socket) do
    events = [event | socket.assigns.recent_events] |> Enum.take(10)
    {:noreply, assign(socket, recent_events: events)}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp load_analytics(device_id) do
    case CVEDIX.get_instance(device_id) do
      {:ok, instance} ->
        case Analytics.get_analytics_entities(instance.instance_id) do
          {:ok, entities} ->
            # Parse all area types from analytics_entities response
            zones = parse_all_areas(entities)
            # Parse all line types from analytics_entities response
            lines = parse_all_lines(entities)
            {instance, zones, lines}
          _ ->
            {instance, [], []}
        end

      _ ->
        {nil, [], []}
    end
  end

  # Parse all area types from analytics_entities response
  defp parse_all_areas(entities) do
    area_keys = [
      "intrusionAreas", "crossingAreas", "loiteringAreas", "crowdingAreas",
      "occupancyAreas", "crowdEstimationAreas", "dwellingAreas", 
      "armedPersonAreas", "fallenPersonAreas", "objectLeftAreas", "objectRemovedAreas"
    ]

    Enum.flat_map(area_keys, fn key ->
      entities
      |> Map.get(key, [])
      |> Enum.map(&normalize_area/1)
    end)
  end

  # Parse all line types from analytics_entities response
  defp parse_all_lines(entities) do
    line_keys = ["crossingLines", "countingLines", "tailgatingLines"]

    Enum.flat_map(line_keys, fn key ->
      entities
      |> Map.get(key, [])
      |> Enum.map(&normalize_line/1)
    end)
  end

  defp normalize_area(area) do
    raw_coords = area["coordinates"]
    Logger.debug("[AnalyticsTab] normalize_area: name=#{area["name"]}, coords_count=#{length(raw_coords || [])}")
    
    # Base fields
    normalized = %{
      area_id: area["id"],
      name: area["name"],
      type: area["type"],
      coordinates: normalize_coords(raw_coords),
      classes: area["classes"] || [],
      color: normalize_color(area["color"])
    }
    
    # Add optional type-specific fields
    normalized
    |> maybe_put(:seconds, area["seconds"])
    |> maybe_put(:object_count, area["objectCount"])
  end
  
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_line(line) do
    %{
      line_id: line["id"],
      name: line["name"],
      type: line["type"],
      coordinates: normalize_coords(line["coordinates"]),
      classes: line["classes"] || [],
      color: normalize_color(line["color"])
    }
    |> maybe_put(:seconds, line["seconds"])
    |> maybe_put(:direction, line["direction"])
  end

  defp normalize_coords(coords) when is_list(coords) do
    Logger.debug("[AnalyticsTab] Raw coords from API: #{inspect(coords)}")
    result = Enum.map(coords, fn
      %{"x" => x, "y" => y} -> %{x: x, y: y}
      %{x: x, y: y} -> %{x: x, y: y}
      [x, y] when is_number(x) and is_number(y) -> %{x: x, y: y}
      c -> 
        Logger.warning("[AnalyticsTab] Unknown coord format: #{inspect(c)}")
        c
    end)
    Logger.debug("[AnalyticsTab] Normalized coords: #{inspect(result)}")
    result
  end
  defp normalize_coords(_), do: []

  # Convert color from 0-1 range to 0-255 range for canvas rendering
  defp normalize_color([r, g, b, a]) when is_float(r) or is_float(g) or is_float(b) or is_float(a) do
    [round(r * 255), round(g * 255), round(b * 255), round(a * 255)]
  end
  defp normalize_color(color) when is_list(color) and length(color) == 4, do: color
  defp normalize_color(_), do: [255, 0, 0, 200]
  # Convert color to 0-1 range for CVEDIX API (API requires values <= 1)
  # Use integers (0 or 1) not floats
  defp normalize_color_to_api([r, g, b, a]) when r > 1 or g > 1 or b > 1 or a > 1 do
    # Convert from 0-255 to 0-1 and round to integers 0 or 1
    [round(r / 255), round(g / 255), round(b / 255), round(a / 255)]
  end
  defp normalize_color_to_api([r, g, b, a]) when is_float(r) or is_float(g) or is_float(b) or is_float(a) do
    # Convert floats to integers 0 or 1
    [round(r), round(g), round(b), round(a)]
  end
  defp normalize_color_to_api(color) when is_list(color) and length(color) == 4, do: color
  defp normalize_color_to_api(_), do: [1, 0, 0, 1]

  defp find_type_info("zone:" <> id), do: Enum.find(@zone_types, &(&1.id == id))
  defp find_type_info("line:" <> id), do: Enum.find(@line_types, &(&1.id == id))
  defp find_type_info(_), do: nil

  # Mapping from UI zone type to API type name
  @zone_type_mapping %{
    "intrusion" => "AreaIntrusion",
    "crossing" => "AreaCrossing",
    "loitering" => "AreaLoitering",
    "object_removed" => "AreaObjectRemoved",
    "object_left" => "AreaObjectLeft",
    "crowding" => "AreaCrowding",
    "occupancy" => "AreaOccupancy",
    "crowd_estimation" => "AreaCrowdEstimation",
    "dwelling" => "AreaDwelling",
    "armed_person" => "AreaArmedPerson",
    "fallen_person" => "AreaFallenPerson"
  }

  # Mapping from UI line type to API type name
  @line_type_mapping %{
    "tailgating" => "LineTailgating",
    "crossing" => "LineCrossing",
    "counting" => "LineCounting"
  }

  defp get_rules_for_type(type_id, zones) do
    api_type = Map.get(@zone_type_mapping, type_id)
    Enum.filter(zones, fn zone -> zone.type == api_type end)
  end

  defp get_lines_for_type(type_id, lines) do
    api_type = Map.get(@line_type_mapping, type_id)
    Enum.filter(lines, fn line -> line.type == api_type end)
  end

  defp status_color("running"), do: "text-green-400"
  defp status_color("stopped"), do: "text-yellow-400"
  defp status_color("error"), do: "text-red-400"
  defp status_color(_), do: "text-white/80"

  defp maybe_add_seconds(params, %{"seconds" => s}) when is_binary(s) do
    Map.put(params, :seconds, String.to_integer(s))
  end
  defp maybe_add_seconds(params, _), do: params

  defp maybe_add_count(params, %{"object_count" => c}) when is_binary(c) do
    Map.put(params, :object_count, String.to_integer(c))
  end
  defp maybe_add_count(params, _), do: params

  defp maybe_add_direction(params, %{"direction" => d}) when is_binary(d) do
    Map.put(params, :direction, d)
  end
  defp maybe_add_direction(params, _), do: params

  # For crossing (Area Enter/Exit) zones: add areaEvent and ignoreStationaryObject
  defp maybe_add_crossing_params(params, "zone:crossing", socket) do
    params
    |> Map.put(:areaEvent, socket.assigns.pending_area_event)
    |> Map.put(:ignoreStationaryObject, socket.assigns.pending_ignore_stationary)
  end
  defp maybe_add_crossing_params(params, _type, _socket), do: params

  # For tailgating lines: add direction from socket assigns
  defp maybe_add_tailgating_params(params, "line:tailgating", socket) do
    Map.put(params, :direction, socket.assigns.pending_direction)
  end
  # For crossing lines: add direction from socket assigns
  defp maybe_add_tailgating_params(params, "line:crossing", socket) do
    Map.put(params, :direction, socket.assigns.pending_direction)
  end
  defp maybe_add_tailgating_params(params, _type, _socket), do: params

  # Convert 0-1 color values to CSS rgba format for display
  defp color_to_css([r, g, b, a]) do
    "rgba(#{r * 255}, #{g * 255}, #{b * 255}, #{a})"
  end
  defp color_to_css(_), do: "rgba(255, 0, 0, 1)"

  # --------------------------------------------------------------------------
  # Private API Helpers
  # --------------------------------------------------------------------------

  defp set_attributes_extraction(instance_id, mode) do
    # Call CVEDIX API to set attributes extraction mode
    CVEDIX.Client.put("/v1/securt/instance/#{instance_id}/attributes_extraction", %{mode: mode})
  end

  defp set_feature_extraction(instance_id, types) do
    # Call CVEDIX API to set feature extraction types
    CVEDIX.Client.put("/v1/securt/instance/#{instance_id}/feature_extraction", %{types: types})
  end

  defp set_face_detection(instance_id, enable) do
    # Call CVEDIX API to enable/disable face detection
    # This sets the flag in SecuRTFeatureManager so pipeline builder knows
    # to auto-add face_detector node on next pipeline build
    CVEDIX.Client.post("/v1/securt/instance/#{instance_id}/face_detection", %{enable: enable})
  end
end
