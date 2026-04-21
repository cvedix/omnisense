defmodule TProNVRWeb.FaceEventsListLive do
  @moduledoc """
  LiveView page for listing face detection events.
  """

  use TProNVRWeb, :live_view

  alias TProNVR.{Devices, Events}
  alias TProNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow e-m-8">
      <h1 class="text-2xl font-bold text-white dark:text-white mb-6">
        Face Detection Events
      </h1>

      <.filter_form meta={@meta} devices={@devices} id="face-event-filter-form" />

      <Flop.Phoenix.table
        id="face-events"
        opts={TProNVRWeb.FlopConfig.table_opts()}
        items={@events}
        meta={@meta}
        path={~p"/events/face"}
      >
        <:col :let={event} label="Device" field={:device_name}>
          {if event.device, do: event.device.name, else: "N/A"}
        </:col>
        <:col :let={event} label="Time" field={:time}>
          {format_date(event.time, event.device && event.device.timezone)}
        </:col>
        <:col :let={event} label="Face Count">
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
            {get_face_count(event.metadata)}
          </span>
        </:col>
        <:col :let={event} label="Faces">
          <div class="flex flex-wrap gap-1">
            <%= for face <- get_faces(event.metadata) do %>
              <span
                class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
                title={"Position: (#{face["x"]}, #{face["y"]}) Size: #{face["w"]}x#{face["h"]}"}
              >
                {face["confidence"]}%
              </span>
            <% end %>
          </div>
        </:col>

        <:action :let={event}>
          <span
            title="View Details"
            phx-click={show_event_details(event)}
            id={"details-#{event.id}"}
            class="cursor-pointer"
          >
            <.icon name="hero-eye-solid" class="w-5 h-5 text-white/80 hover:text-green-500" />
          </span>
        </:action>
      </Flop.Phoenix.table>

      <.pagination meta={@meta} />
    </div>

    <!-- Event Details Modal -->
    <div
      id="event-details-modal"
      class="fixed inset-0 bg-black bg-opacity-75 flex justify-center items-center hidden z-50"
    >
      <div class="bg-black rounded-lg p-6 max-w-lg w-full mx-4">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-medium text-white dark:text-white">Event Details</h3>
          <button
            class="text-white/80 hover:text-white/60"
            phx-click={JS.add_class("hidden", to: "#event-details-modal")}
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </button>
        </div>
        <pre
          id="event-details-content"
          class="bg-green-900 dark:bg-black p-4 rounded text-sm overflow-auto max-h-96 text-white dark:text-white"
        ></pre>
      </div>
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: to_form(meta), meta: meta, devices: devices)

    ~H"""
    <.form for={@form} id={@id} phx-change="filter-events" class="flex items-baseline space-x-4 mb-6">
      <Flop.Phoenix.filter_fields
        :let={f}
        form={@form}
        fields={[
          device_id: [
            type: "select",
            options: Enum.map(@devices, &{&1.name, &1.id}),
            prompt: "All Devices"
          ],
          time: [op: :>=, label: "From"],
          time: [op: :<=, label: "To"]
        ]}
      >
        <div>
          <.input
            class="border rounded p-1"
            field={f.field}
            label={f.label}
            type={f.type}
            phx-debounce="500"
            {f.rest}
          />
        </div>
      </Flop.Phoenix.filter_fields>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       devices: Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(socket.assigns.current_user),
       filter_params: %{},
       pagination_params: %{},
       sort_params: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    load_face_events(params, socket)
  end

  @impl true
  def handle_event("filter-events", filter_params, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(to: Routes.face_events_list_path(socket, :list, filter_params))}
  end

  @impl true
  def handle_event("paginate", pagination_params, socket) do
    pagination_params = Map.merge(socket.assigns.pagination_params, pagination_params)

    params =
      Map.merge(socket.assigns.filter_params, pagination_params)
      |> Map.merge(socket.assigns.sort_params)

    {:noreply,
     socket
     |> assign(pagination_params: pagination_params)
     |> push_patch(to: Routes.face_events_list_path(socket, :list, params), replace: true)}
  end

  defp load_face_events(params, socket) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    # Filter only face_detection events
    params = Map.put(params, "filters", [%{"field" => "type", "op" => "==", "value" => "face_detection"}])

    case Events.list_events(params) do
      {:ok, {events, meta}} ->
        {:noreply, assign(socket, meta: meta, events: events, sort_params: sort_params)}

      {:error, meta} ->
        {:noreply, assign(socket, meta: meta, events: [])}
    end
  end

  defp format_date(nil, _timezone), do: "N/A"
  defp format_date(date, nil), do: Calendar.strftime(date, "%b %d, %Y %H:%M:%S")

  defp format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y %H:%M:%S %Z")
  end

  defp get_face_count(nil), do: 0
  defp get_face_count(%{"face_count" => count}), do: count
  defp get_face_count(%{face_count: count}), do: count
  defp get_face_count(_), do: 0

  defp get_faces(nil), do: []
  defp get_faces(%{"faces" => faces}) when is_list(faces), do: faces
  defp get_faces(%{faces: faces}) when is_list(faces), do: Enum.map(faces, &stringify_keys/1)
  defp get_faces(_), do: []

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp show_event_details(event) do
    details = Jason.encode!(event.metadata, pretty: true)

    JS.remove_class("hidden", to: "#event-details-modal")
    |> JS.set_attribute({"data-details", details}, to: "#event-details-content")
    |> JS.dispatch("face-events:show-details", to: "#event-details-content")
  end
end
