defmodule TProNVRWeb.DeviceListLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  import TProNVR.Authorization

  alias TProNVR.Devices
  alias TProNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="grow p-6 bg-black font-mono text-green-500 min-h-screen">
      <div class="flex items-center justify-between mb-6 border-b border-green-900/50 pb-4">
        <h1 class="text-xl font-bold tracking-widest uppercase">NODE_FLEET_MANAGEMENT</h1>
        <div :if={@current_user.role == :admin}>
          <.link href={~p"/devices/new"}>
            <.button class="shadow-[0_0_15px_rgba(34,197,94,0.3)]"><.icon name="hero-plus-solid" class="h-4 w-4 mr-2" />PROVISION_NODE</.button>
          </.link>
        </div>
      </div>

      <.table
        id="devices"
        rows={@devices}
        row_click={fn device -> JS.navigate(~p"/devices/#{device.id}/details") end}
        row_id={fn device -> "device-row-#{device.id}" end}
      >
        <:col :let={device} label="Id">{device.id}</:col>
        <:col :let={device} label="Type">{get_type_label(device.type)}</:col>
        <:col :let={device} label="Name">{device.name}</:col>
        <:col :let={device} label="Vendor">{device.vendor || "N/A"}</:col>
        <:col :let={device} label="Timezone">{device.timezone}</:col>
        <:col :let={device} label="State">
          <div class="flex items-center">
            <div class={
              ["h-2 w-2 rounded-none mr-3 shadow-[0_0_5px_rgba(0,0,0,0.5)]"] ++
                case device.state do
                  :recording -> ["bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.5)]"]
                  :streaming -> ["bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]"]
                  :failed -> ["bg-yellow-500 shadow-[0_0_8px_rgba(234,179,8,0.5)]"]
                  :stopped -> ["bg-green-900"]
                end
            }>
            </div>
            <span class="font-bold tracking-widest leading-none">{String.upcase(to_string(device.state))}</span>
          </div>
        </:col>
        <:action :let={device}>
          <.three_dot
            :if={@current_user.role == :admin}
            id={"dropdownMenuIconButton_#{device.id}"}
            dropdown_id={"dropdownDots_#{device.id}"}
          />
          <div
            id={"dropdownDots_#{device.id}"}
            class="z-10 hidden text-left bg-black border border-green-500 shadow-[0_0_15px_rgba(0,128,0,0.2)] rounded-none w-44"
          >
            <ul
              class="py-1 text-xs font-bold tracking-widest text-green-500 uppercase"
              aria-labelledby={"dropdownMenuIconButton_#{device.id}"}
            >
              <li>
                <.link
                  href={~p"/devices/#{device.id}"}
                  class="block px-4 py-2 hover:bg-green-900/40 hover:text-green-300 border-l-2 border-transparent hover:border-green-500 transition-all"
                >
                  CONFIGURE
                </.link>
              </li>
              <li>
                <.link
                  href={~p"/webrtc/#{device.id}"}
                  target="_blank"
                  class="block px-4 py-2 hover:bg-green-900/40 hover:text-green-400 border-l-2 border-transparent hover:border-green-500 transition-all text-green-400"
                >
                  TEST_WEBRTC
                </.link>
              </li>
              <li>
                <.link
                  phx-click={show_modal("delete-device-modal-#{device.id}")}
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-red-900/40 text-red-500 hover:text-red-400 border-l-2 border-transparent hover:border-red-500 transition-all"
                >
                  DECOMMISSION
                </.link>
              </li>
              <li>
                <.link
                  :if={not Device.recording?(device)}
                  phx-click="start-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-green-900/40 hover:text-green-300 border-l-2 border-transparent hover:border-green-500 transition-all"
                >
                  INIT_RECORD
                </.link>
              </li>
              <li>
                <.link
                  :if={Device.recording?(device)}
                  phx-click="stop-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-green-900/40 hover:text-green-300 border-l-2 border-transparent hover:border-green-500 transition-all"
                >
                  HALT_RECORD
                </.link>
              </li>
            </ul>
          </div>
        </:action>
        <:action :let={device}>
          <.modal id={"delete-device-modal-#{device.id}"}>
            <div class="bg-black border border-red-500 p-8 shadow-[0_0_20px_rgba(239,68,68,0.3)] relative">
              <div class="absolute top-0 right-0 w-2 h-2 border-t border-r border-red-500"></div>
              <div class="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-red-500"></div>
              
              <h2 class="text-xl text-red-500 font-bold mb-4 tracking-widest uppercase border-b border-red-900/50 pb-2 flex items-center">
                <.icon name="hero-exclamation-triangle" class="w-6 h-6 mr-3" />
                CONFIRM_DECOMMISSION
              </h2>
              <div class="text-green-500 text-sm tracking-widest font-mono space-y-4">
                <p>ASSET_ID: <span class="text-white font-bold"><%= device.id %></span></p>
                <p>WARNING: Data volume remains intact. Manual purge required at path:</p>
                <div class="bg-red-900/20 border-l-2 border-red-500 p-4 mt-2">
                  <code class="text-red-400 font-bold break-all">
                    {Device.base_dir(device)}
                  </code>
                </div>
              </div>
              <div class="mt-8 flex gap-4">
                <button
                  phx-click="delete-device"
                  phx-value-device={device.id}
                  class="bg-red-600 text-white hover:bg-red-500 py-2 px-6 rounded-none font-bold tracking-widest uppercase shadow-[0_0_10px_rgba(239,68,68,0.4)] transition-colors border border-red-500"
                >
                  EXECUTE_PURGE
                </button>
                <button
                  phx-click={hide_modal("delete-device-modal-#{device.id}")}
                  class="bg-green-900/30 text-green-500 hover:bg-green-900/50 hover:text-green-400 py-2 px-6 rounded-none font-bold tracking-widest uppercase transition-colors border border-green-700 hover:border-green-500"
                >
                  ABORT
                </button>
              </div>
            </div>
          </.modal>
        </:action>
      </.table>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    devices = Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(user)
    {:ok, assign(socket, devices: devices)}
  end

  def handle_event("delete-device", %{"device" => device_id}, socket) do
    delete_device(socket, device_id)
  end

  def handle_event("stop-recording", %{"device" => device_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, device_id, :stopped)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  def handle_event("start-recording", %{"device" => device_id}, socket) do
    user = socket.assigns.current_user

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, device_id, :recording)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  defp delete_device(socket, device_id) do
    devices = socket.assigns.devices
    user = socket.assigns.current_user

    with :ok <- authorize(user, :device, :delete),
         %Device{} = device <- Enum.find(devices, &(&1.id == device_id)) do
      # Delete all associated analytics data
      delete_device_analytics_data(device_id)

      # Delete associated CVEDIX instance if exists
      delete_cvedix_instance(device_id)

      # Delete the device
      case Devices.delete(device) do
        :ok ->
          socket =
            socket
             |> assign(devices: Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(socket.assigns.current_user))
            |> put_flash(:info, "Device #{device.name} deleted")

          {:noreply, socket}

        _error ->
          {:noreply, put_flash(socket, :error, "could not delete device")}
      end
    else
      _other -> {:noreply, put_flash(socket, :error, "could not delete device")}
    end
  end

  defp delete_cvedix_instance(device_id) do
    alias TProNVR.CVEDIX.{CvedixInstance, Instance}
    alias TProNVR.Repo
    import Ecto.Query

    # Find the instance linked to this device
    case Repo.one(from i in CvedixInstance, where: i.device_id == ^device_id) do
      nil ->
        :ok

      %CvedixInstance{instance_id: instance_id, id: cvedix_id} = db_instance ->
        # Stop and delete from CVEDIX-RT
        Instance.stop(instance_id)
        Instance.unload(instance_id)
        Instance.delete(instance_id)

        # Delete intrusion areas linked to this instance
        Repo.delete_all(from a in TProNVR.CVEDIX.IntrusionArea, where: a.cvedix_instance_id == ^cvedix_id)

        # Delete from database
        Repo.delete(db_instance)
        :ok
    end
  end

  defp delete_device_analytics_data(device_id) do
    alias TProNVR.Repo
    import Ecto.Query

    # Delete AI Analytics Events
    Repo.delete_all(from e in TProNVR.CVEDIX.AIAnalyticsEvent, where: e.device_id == ^device_id)

    # Delete AI Analytics Tracks
    Repo.delete_all(from t in TProNVR.CVEDIX.Track, where: t.device_id == ^device_id)

    # Delete AI Crops
    Repo.delete_all(from c in TProNVR.CVEDIX.Crop, where: c.device_id == ^device_id)

    # Delete AI Attributes
    Repo.delete_all(from a in TProNVR.CVEDIX.Attribute, where: a.device_id == ^device_id)

    # Delete Intrusion Events
    Repo.delete_all(from i in TProNVR.CVEDIX.IntrusionEvent, where: i.device_id == ^device_id)

    # Delete Statistics
    Repo.delete_all(from s in TProNVR.CVEDIX.Statistic, where: s.device_id == ^device_id)

    :ok
  end

  defp update_device_state(socket, device_id, new_state) do
    devices = socket.assigns.devices

    with %Device{} = device <- Enum.find(devices, &(&1.id == device_id)),
         {:ok, _device} <- Devices.update_state(device, new_state) do
      {:noreply, assign(socket, devices: Devices.list() |> TProNVR.Accounts.Permissions.filter_devices(socket.assigns.current_user))}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not update device state")}
    end
  end

  defp get_type_label(:ip), do: "IP Camera"
  defp get_type_label(:file), do: "File"
  defp get_type_label(:webcam), do: "Webcam"

  defp unauthorized(socket, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> then(&{reply, &1})
  end
end
