defmodule TProNVRWeb.GstWebRTCChannel do
  @moduledoc """
  Phoenix Channel for GStreamer WebRTC signaling.
  
  Handles WebRTC signaling between browser and GStreamer webrtcbin
  for ultra-low latency live streaming.
  """
  
  use TProNVRWeb, :channel
  
  require Logger
  
  alias TProNVR.Gst.WebRTCManager
  
  @impl true
  def join("gst_webrtc:" <> device_id, _params, socket) do
    device = TProNVR.Devices.get!(device_id)
    
    # Start WebRTC manager if not running
    case ensure_webrtc_manager(device) do
      :ok ->
        # Add this channel as a peer
        peer_id = self()
        case WebRTCManager.add_peer(device_id, peer_id) do
          :ok ->
            {:ok, assign(socket, device: device, peer_id: peer_id)}
            
          {:error, reason} ->
            {:error, %{reason: reason}}
        end
        
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
  
  @impl true
  def handle_in("answer", answer_json, socket) do
    answer = Jason.decode!(answer_json)
    WebRTCManager.send_answer(socket.assigns.device.id, socket.assigns.peer_id, answer)
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("ice_candidate", candidate_json, socket) do
    candidate = Jason.decode!(candidate_json)
    WebRTCManager.send_ice_candidate(socket.assigns.device.id, socket.assigns.peer_id, candidate)
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:offer, offer}, socket) do
    push(socket, "offer", %{data: Jason.encode!(offer)})
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:ice_candidate, candidate}, socket) do
    push(socket, "ice_candidate", %{data: Jason.encode!(candidate)})
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:error, message}, socket) do
    push(socket, "error", %{message: message})
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(msg, socket) do
    Logger.debug("[GstWebRTCChannel] Unhandled: #{inspect(msg)}")
    {:noreply, socket}
  end
  
  @impl true
  def terminate(_reason, socket) do
    WebRTCManager.remove_peer(socket.assigns.device.id, socket.assigns.peer_id)
    :ok
  end
  
  # ============================================================
  # Private Functions
  # ============================================================
  
  defp ensure_webrtc_manager(device) do
    # Check if WebRTC manager is already running for this device
    case Registry.lookup(TProNVR.Gst.Registry, {:webrtc_manager, device.id}) do
      [{_pid, _}] ->
        :ok
        
      [] ->
        # Start a new WebRTC manager
        rtsp_url = build_rtsp_url(device)
        
        case DynamicSupervisor.start_child(
          TProNVR.PipelineSupervisor,
          {WebRTCManager, device_id: device.id, rtsp_url: rtsp_url}
        ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
  
  defp build_rtsp_url(device) do
    credentials = 
      if device.credentials do
        "#{device.credentials.username}:#{device.credentials.password}@"
      else
        ""
      end
    
    "rtsp://#{credentials}#{device.config.host}:#{device.config.port}/#{device.config.path}"
  end
end
