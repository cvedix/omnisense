defmodule TProNVRWeb.EventNotificationHook do
  @moduledoc """
  LiveView on_mount hook that subscribes to AI event notifications.
  Pushes events to the EventToast JS hook for toast rendering.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias TProNVR.CVEDIX.Crop
  alias TProNVR.Repo

  import Ecto.Query

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TProNVR.PubSub, "ai_events:notifications")
    end

    devices = TProNVR.Devices.list()
    device_map = Map.new(devices, fn d -> {d.id, d.name} end)

    {:cont,
     socket
     |> assign(:_notification_device_map, device_map)
     |> attach_hook(:ai_event_notifications, :handle_info, &handle_notification/2)}
  end

  defp handle_notification({:ai_event_notification, %{event_type: "__fs_attr_area"}}, socket) do
    {:cont, socket}
  end

  defp handle_notification({:ai_event_notification, event}, socket) do
    # Also ignore if area_name or event_subtype matches __fs_attr_area just in case
    if Map.get(event, :area_name) == "__fs_attr_area" or Map.get(event, :event_subtype) == "__fs_attr_area" do
      {:cont, socket}
    else
      device_map = socket.assigns[:_notification_device_map] || %{}
      toast = build_toast(event, device_map)

      # Only show notifications that have a thumbnail image
      if toast.thumbnail do
        {:cont, push_event(socket, "ai_event_toast", toast)}
      else
        {:cont, socket}
      end
    end
  end

  defp handle_notification(_msg, socket), do: {:cont, socket}

  defp build_toast(event, device_map) do
    device_name = Map.get(device_map, event.device_id, "Unknown Device")
    thumbnail = get_thumbnail(event)
    duration = calculate_duration(event)
    time_str = Calendar.strftime(event.inserted_at, "%H:%M:%S")

    %{
      event_type: event.event_type,
      area_name: event.area_name || "Unknown Area",
      device_name: device_name,
      object_class: event.object_class,
      thumbnail: thumbnail,
      duration: duration,
      time_str: time_str
    }
  end

  defp get_thumbnail(event) do
    if event.ref_tracking_id do
      crop = from(c in Crop,
        where: c.ref_tracking_id == ^event.ref_tracking_id,
        order_by: [desc: c.inserted_at],
        limit: 1
      ) |> Repo.one()

      cond do
        crop && crop.base64_image ->
          "data:image/jpeg;base64," <> crop.base64_image
        crop && crop.image_path && File.exists?(crop.image_path) ->
          data = File.read!(crop.image_path)
          "data:image/jpeg;base64," <> Base.encode64(data)
        true -> nil
      end
    end
  end

  defp calculate_duration(event) do
    raw = event.raw_data || %{}
    case raw["duration_seconds"] do
      nil -> nil
      seconds when is_number(seconds) ->
        cond do
          seconds < 60 -> "#{round(seconds)}s"
          seconds < 3600 -> "#{div(round(seconds), 60)}m #{rem(round(seconds), 60)}s"
          true -> "#{div(round(seconds), 3600)}h #{div(rem(round(seconds), 3600), 60)}m"
        end
      _ -> nil
    end
  end
end
