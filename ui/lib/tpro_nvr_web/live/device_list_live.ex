defmodule TProNVRWeb.DeviceListLive do
  @moduledoc false

  use TProNVRWeb, :live_view

  import TProNVR.Authorization

  alias TProNVR.Devices
  alias TProNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <div :if={@current_user.role == :admin} class="ml-4 sm:ml-0">
        <.link href={~p"/devices/new"}>
          <.button><.icon name="hero-plus-solid" class="h-4 w-4" />Add Device</.button>
        </.link>
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
              ["h-2.5 w-2.5 rounded-full mr-2"] ++
                case device.state do
                  :recording -> ["bg-green-500"]
                  :streaming -> ["bg-green-500"]
                  :failed -> ["bg-red-500"]
                  :stopped -> ["bg-yellow-500"]
                end
            }>
            </div>
            {String.upcase(to_string(device.state))}
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
            class="z-10 hidden text-left bg-black divide-y divide-green-800 rounded-lg shadow w-44 dark:bg-black dark:divide-green-700"
          >
            <ul
              class="py-2 text-sm text-white dark:text-white"
              aria-labelledby={"dropdownMenuIconButton_#{device.id}"}
            >
              <li>
                <.link
                  href={~p"/devices/#{device.id}"}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Update
                </.link>
              </li>
              <li>
                <.link
                  phx-click={show_modal("delete-device-modal-#{device.id}")}
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Delete
                </.link>
              </li>
              <li>
                <.link
                  :if={not Device.recording?(device)}
                  phx-click="start-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Start recording
                </.link>
              </li>
              <li>
                <.link
                  :if={Device.recording?(device)}
                  phx-click="stop-recording"
                  phx-value-device={device.id}
                  class="block px-4 py-2 hover:bg-green-900 dark:hover:bg-green-800 dark:hover:text-white"
                >
                  Stop recording
                </.link>
              </li>
            </ul>
          </div>
        </:action>
        <:action :let={device}>
          <.modal id={"delete-device-modal-#{device.id}"}>
            <div class="bg-green-300 dark:bg-black m-8 rounded">
              <h2 class="text-xl text-white font-bold mb-4">
                Are you sure you want to delete this device? <br />
              </h2>
              <h3>
                The actual recording files are not deleted. <br />
                If you want to delete them delete the following folders: <br />
                <div class="bg-black bg-green-900 rounded-md p-4 mt-2">
                  <code class="text-white font-bold">
                    {Device.base_dir(device)}
                  </code>
                </div>
              </h3>
              <div class="mt-4">
                <button
                  phx-click="delete-device"
                  phx-value-device={device.id}
                  class="bg-red-500 hover:bg-red-600 text-white py-2 px-4 rounded mr-4 font-bold"
                >
                  Confirm Delete
                </button>
                <button
                  phx-click={hide_modal("delete-device-modal-#{device.id}")}
                  class="bg-green-900 hover:bg-green-700 text-white py-2 px-4 rounded font-bold"
                >
                  Cancel
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
    {:ok, assign(socket, devices: Devices.list())}
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
            |> assign(devices: Devices.list())
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
      {:noreply, assign(socket, devices: Devices.list())}
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
