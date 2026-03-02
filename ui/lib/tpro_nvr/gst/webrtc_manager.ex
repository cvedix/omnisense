defmodule TProNVR.Gst.WebRTCManager do
  @moduledoc """
  Manages GStreamer WebRTC server processes for low-latency streaming.
  
  This module:
  - Starts a Python WebRTC server per device
  - Routes signaling messages between Phoenix Channels and GStreamer
  - Handles peer lifecycle (add/remove)
  """
  
  use GenServer
  require Logger
  
  @type peer_id :: pid() | String.t()
  
  defstruct [
    :device_id,
    :rtsp_url,
    :port,
    :peers,
    :ready
  ]
  
  # ============================================================
  # Public API
  # ============================================================
  
  @doc """
  Start the WebRTC manager for a device.
  """
  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    rtsp_url = Keyword.fetch!(opts, :rtsp_url)
    GenServer.start_link(__MODULE__, {device_id, rtsp_url}, name: via_tuple(device_id))
  end
  
  @doc """
  Add a new WebRTC peer (called from Phoenix Channel).
  Returns :ok or {:error, reason}
  """
  @spec add_peer(String.t(), peer_id()) :: :ok | {:error, term()}
  def add_peer(device_id, peer_id) do
    GenServer.call(via_tuple(device_id), {:add_peer, peer_id})
  end
  
  @doc """
  Remove a WebRTC peer.
  """
  @spec remove_peer(String.t(), peer_id()) :: :ok
  def remove_peer(device_id, peer_id) do
    GenServer.cast(via_tuple(device_id), {:remove_peer, peer_id})
  end
  
  @doc """
  Forward an SDP answer from browser to GStreamer.
  """
  @spec send_answer(String.t(), peer_id(), map()) :: :ok
  def send_answer(device_id, peer_id, answer) do
    GenServer.cast(via_tuple(device_id), {:answer, peer_id, answer})
  end
  
  @doc """
  Forward an ICE candidate from browser to GStreamer.
  """
  @spec send_ice_candidate(String.t(), peer_id(), map()) :: :ok
  def send_ice_candidate(device_id, peer_id, candidate) do
    GenServer.cast(via_tuple(device_id), {:ice_candidate, peer_id, candidate})
  end
  
  @doc """
  Stop the WebRTC manager.
  """
  def stop(device_id) do
    GenServer.stop(via_tuple(device_id), :normal)
  end
  
  # ============================================================
  # GenServer Callbacks
  # ============================================================
  
  @impl true
  def init({device_id, rtsp_url}) do
    Logger.info("[WebRTCManager] Starting for device: #{device_id}")
    
    state = %__MODULE__{
      device_id: device_id,
      rtsp_url: rtsp_url,
      port: nil,
      peers: %{},
      ready: false
    }
    
    # Start Python WebRTC server
    {:ok, state, {:continue, :start_server}}
  end
  
  @impl true
  def handle_continue(:start_server, state) do
    case start_python_server(state) do
      {:ok, port} ->
        {:noreply, %{state | port: port}}
        
      {:error, reason} ->
        Logger.error("[WebRTCManager] Failed to start server: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call({:add_peer, _peer_id}, _from, %{ready: false} = state) do
    {:reply, {:error, :not_ready}, state}
  end
  
  @impl true
  def handle_call({:add_peer, peer_id}, _from, state) do
    peer_id_str = peer_id_to_string(peer_id)
    
    # Send message to Python server
    send_to_server(state.port, %{
      type: "add_peer",
      peer_id: peer_id_str
    })
    
    # Track the peer
    new_peers = Map.put(state.peers, peer_id_str, peer_id)
    {:reply, :ok, %{state | peers: new_peers}}
  end
  
  @impl true
  def handle_cast({:remove_peer, peer_id}, state) do
    peer_id_str = peer_id_to_string(peer_id)
    
    send_to_server(state.port, %{
      type: "remove_peer",
      peer_id: peer_id_str
    })
    
    new_peers = Map.delete(state.peers, peer_id_str)
    {:noreply, %{state | peers: new_peers}}
  end
  
  @impl true
  def handle_cast({:answer, peer_id, answer}, state) do
    peer_id_str = peer_id_to_string(peer_id)
    
    send_to_server(state.port, %{
      type: "answer",
      peer_id: peer_id_str,
      sdp: answer["sdp"]
    })
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:ice_candidate, peer_id, candidate}, state) do
    peer_id_str = peer_id_to_string(peer_id)
    
    send_to_server(state.port, %{
      type: "ice_candidate",
      peer_id: peer_id_str,
      mline_index: candidate["sdpMLineIndex"] || 0,
      candidate: candidate["candidate"]
    })
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Parse JSON messages from Python server
    data
    |> String.split("\n", trim: true)
    |> Enum.each(&handle_server_message(&1, state))
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    handle_server_message(line, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("[WebRTCManager] Python server exited with status: #{status}")
    {:stop, {:server_exit, status}, state}
  end
  
  @impl true
  def handle_info(msg, state) do
    Logger.debug("[WebRTCManager] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.info("[WebRTCManager] Terminating: #{inspect(reason)}")
    if state.port do
      send_to_server(state.port, %{type: "stop"})
      Port.close(state.port)
    end
    :ok
  end
  
  # ============================================================
  # Private Functions
  # ============================================================
  
  defp via_tuple(device_id) do
    {:via, Registry, {TProNVR.Gst.Registry, {:webrtc_manager, device_id}}}
  end
  
  defp start_python_server(state) do
    script_path = Path.join(:code.priv_dir(:tpro_nvr), "gst_webrtc/webrtc_server.py")
    
    cmd = "python3 #{script_path} --rtsp-url \"#{state.rtsp_url}\""
    
    try do
      port = Port.open({:spawn, cmd}, [
        :binary,
        :exit_status,
        {:line, 16384},
        :use_stdio,
        :stderr_to_stdout
      ])
      
      Logger.info("[WebRTCManager] Started Python server for #{state.device_id}")
      {:ok, port}
    rescue
      e in ArgumentError ->
        {:error, {:invalid_command, Exception.message(e)}}
      e ->
        {:error, {:port_open_failed, Exception.message(e)}}
    end
  end
  
  defp send_to_server(port, message) do
    json = Jason.encode!(message) <> "\n"
    Port.command(port, json)
  end
  
  defp handle_server_message(json_str, state) do
    case Jason.decode(json_str) do
      {:ok, %{"type" => "ready"}} ->
        Logger.info("[WebRTCManager] Server ready for #{state.device_id}")
        # Update state - need to send ourselves a message since we're in handle_info
        send(self(), :server_ready)
        
      {:ok, %{"type" => "offer", "peer_id" => peer_id, "sdp" => sdp}} ->
        # Forward offer to Phoenix Channel peer
        forward_to_peer(state.peers, peer_id, {:offer, %{"type" => "offer", "sdp" => sdp}})
        
      {:ok, %{"type" => "ice_candidate", "peer_id" => peer_id} = msg} ->
        # Forward ICE candidate to peer
        candidate = %{
          "candidate" => msg["candidate"],
          "sdpMLineIndex" => msg["mline_index"]
        }
        forward_to_peer(state.peers, peer_id, {:ice_candidate, candidate})
        
      {:ok, %{"type" => "error", "peer_id" => peer_id, "message" => error_msg}} ->
        Logger.error("[WebRTCManager] Peer #{peer_id} error: #{error_msg}")
        forward_to_peer(state.peers, peer_id, {:error, error_msg})
        
      {:ok, %{"type" => "pong"}} ->
        :ok
        
      {:error, _} ->
        Logger.debug("[WebRTCManager] Non-JSON output: #{json_str}")
    end
  end
  
  defp forward_to_peer(peers, peer_id_str, message) do
    case Map.get(peers, peer_id_str) do
      nil ->
        Logger.warning("[WebRTCManager] Unknown peer: #{peer_id_str}")
        
      peer_pid when is_pid(peer_pid) ->
        send(peer_pid, message)
        
      _ ->
        :ok
    end
  end
  
  defp peer_id_to_string(peer_id) when is_pid(peer_id) do
    peer_id |> :erlang.pid_to_list() |> to_string()
  end
  
  defp peer_id_to_string(peer_id) when is_binary(peer_id), do: peer_id
end
