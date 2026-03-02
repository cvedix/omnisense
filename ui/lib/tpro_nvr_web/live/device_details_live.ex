defmodule TProNVRWeb.DeviceDetailsLive do
  use TProNVRWeb, :live_view

  require Logger

  alias TProNVR.Devices
  alias TProNVRWeb.DeviceTabs.{AnalyticsTab, TrackLogTab, CropLogTab, AIEventsLogTab, AttributeLogTab, EventsListTab, RecordingsListTab}
  alias TProNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <h2 class="text-xl font-semibold text-white mb-4">
        {@device.name}
      </h2>
      <.tabs id="device-details-tabs" active_tab={@active_tab} on_change={:tab_changed}>
        <:tab id="details" label="Details" />
        <:tab id="recordings" label="Recordings" />
        <:tab id="stats" label="Stats" />
        <:tab id="settings" label="Settings" />
        <:tab id="events" label="Events" />
        <:tab id="ai-analytics" label="AI Analytics" />
        <:tab id="ai-track-log" label="AI Track Log" />
        <:tab id="ai-crop-log" label="AI Crop Log" />
        <:tab id="ai-attribute-log" label="AI Attribute Log" />
        <:tab id="ai-events" label="AI Event Log" />
        
    <!-- device details tab -->
        <:tab_content for="details">
          <ul class="divide-y divide-green-800 text-white rounded-md shadow-sm max-w-xl ">
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-white/80">Name:</span>
              <span>{@device.name}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-white/80">Type:</span>
              <span>{@device.type}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-white/80">Status:</span>
              <span class="font-bold flex items-center gap-1">
                <div class={
                  ["h-2.5 w-2.5 rounded-full mr-2"] ++
                    case @device.state do
                      :recording -> ["bg-green-500"]
                      :streaming -> ["bg-green-500"]
                      :failed -> ["bg-red-500"]
                      :stopped -> ["bg-yellow-500"]
                    end
                }>
                </div>
                {String.upcase(to_string(@device.state))}
              </span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-white/80">Created At:</span>
              <span>{Calendar.strftime(@device.inserted_at, "%b %d, %Y %H:%M:%S %Z")}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-white/80">Timezone:</span>
              <span>{@device.timezone}</span>
            </li>
          </ul>
        </:tab_content>
        
    <!-- recordings tab -->
        <:tab_content for="recordings">
          <.live_component
            module={RecordingsListTab}
            id="recordings_list_tab"
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- stats tab-->
        <:tab_content for="stats">
          <div class="text-center text-white/60 dark:text-white/80">Stats tab coming soon...</div>
        </:tab_content>

        <:tab_content for="settings">
          <div class="text-center text-white/60 dark:text-white/80">
            settings tab coming soon...
          </div>
        </:tab_content>
        
    <!-- events tab-->
        <:tab_content for="events">
          <.live_component
            id="events_list_tab"
            module={EventsListTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- ai-track-log tab -->
        <:tab_content for="ai-track-log">
          <.live_component
            id="track_log_tab"
            module={TrackLogTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- ai-crop-log tab -->
        <:tab_content for="ai-crop-log">
          <.live_component
            id="crop_log_tab"
            module={CropLogTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- ai-attribute-log tab -->
        <:tab_content for="ai-attribute-log">
          <.live_component
            id="attribute_log_tab"
            module={AttributeLogTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- ai-events tab -->
        <:tab_content for="ai-events">
          <.live_component
            id="ai_events_log_tab"
            module={AIEventsLogTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
        
    <!-- ai-analytics tab (intrusion detection) -->
        <:tab_content for="ai-analytics">
          <.live_component
            id="analytics_tab"
            module={AnalyticsTab}
            device={@device}
            params={@params}
          />
        </:tab_content>
      </.tabs>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)

    active_tab = params["tab"] || "details"

    {:ok,
     assign(socket,
       device: device,
       active_tab: active_tab
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, params["tab"] || socket.assigns.active_tab)
     |> assign(:params, params)}
  end

  @impl true
  def handle_info({:auto_refresh_component, myself}, socket) do
    send_update(myself, %{action: :auto_refresh_tick})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    params =
      socket.assigns.params
      |> Map.put("tab", tab)
      |> Map.put("filter_params", %{})
      |> Map.drop(["order_by", "order_direction"])

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:params, params)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
  end

  def update_params(tab, id) do
    send_update(tab, id: id, params: %{})
  end

  # Forward drawing events from AnalyticsDrawing hook to AnalyticsTab component
  @impl true
  def handle_event("drawing_complete", params, socket) do
    send_update(AnalyticsTab, id: "analytics_tab", drawing_complete: params)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_edited_coordinates", params, socket) do
    require Logger
    Logger.info("[DeviceDetailsLive] RECEIVED save_edited_coordinates: #{inspect(params)}")
    send_update(AnalyticsTab, id: "analytics_tab", save_edited_coordinates: params)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_edit", _params, socket) do
    {:noreply, push_event(socket, "trigger_save_edit", %{})}
  end

  # Catch-all for debugging
  @impl true
  def handle_event(event, params, socket) do
    require Logger
    Logger.warning("[DeviceDetailsLive] Unhandled event: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end
end
