defmodule TProNVR.SystemMonitor do
  @moduledoc """
  GenServer for collecting system metrics: CPU temperature, CPU usage, RAM usage, Disk usage.
  Broadcasts metrics every 5 seconds via PubSub.
  """
  
  use GenServer
  require Logger
  
  @topic "system_metrics"
  @interval 5_000  # 5 seconds
  
  # ============================================================
  # Public API
  # ============================================================
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  def subscribe do
    Phoenix.PubSub.subscribe(TProNVR.PubSub, @topic)
  end
  
  # ============================================================
  # GenServer Callbacks
  # ============================================================
  
  @impl true
  def init(_) do
    # Schedule first tick
    send(self(), :tick)
    {:ok, %{metrics: collect_metrics()}}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  @impl true
  def handle_info(:tick, _state) do
    metrics = collect_metrics()
    
    # Broadcast to subscribers
    Phoenix.PubSub.broadcast(TProNVR.PubSub, @topic, {:system_metrics, metrics})
    
    # Schedule next tick
    Process.send_after(self(), :tick, @interval)
    
    {:noreply, %{metrics: metrics}}
  end
  
  # ============================================================
  # Private Functions
  # ============================================================
  
  defp collect_metrics do
    %{
      cpu_temp: get_cpu_temp(),
      cpu_usage: get_cpu_usage(),
      ram_usage: get_ram_usage(),
      disk_usage: get_disk_usage()
    }
  end
  
  # Get CPU temperature (Rockchip RK3588 thermal zones)
  defp get_cpu_temp do
    thermal_paths = [
      "/sys/class/thermal/thermal_zone0/temp",
      "/sys/class/thermal/thermal_zone1/temp",
      "/sys/class/thermal/thermal_zone2/temp"
    ]
    
    temps = thermal_paths
    |> Enum.map(&read_temp_file/1)
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(temps) do
      nil
    else
      # Return max temperature
      Enum.max(temps)
    end
  end
  
  defp read_temp_file(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.to_integer()
        |> Kernel./(1000)  # Convert millidegrees to degrees
        |> Float.round(1)
      _ -> nil
    end
  rescue
    _ -> nil
  end
  
  # Get CPU usage using /proc/stat
  defp get_cpu_usage do
    case :memsup.get_system_memory_data() do
      memory_data when is_list(memory_data) ->
        # Use Erlang's cpu_sup if available
        try do
          case :cpu_sup.util() do
            {:all, usage, _, _} -> Float.round(usage, 1)
            usage when is_number(usage) -> Float.round(usage / 1, 1)
            _ -> calculate_cpu_from_proc()
          end
        rescue
          _ -> calculate_cpu_from_proc()
        catch
          _, _ -> calculate_cpu_from_proc()
        end
      _ -> calculate_cpu_from_proc()
    end
  end
  
  defp calculate_cpu_from_proc do
    case File.read("/proc/loadavg") do
      {:ok, content} ->
        [load1 | _] = String.split(content, " ")
        # Convert load average to rough percentage (for 4-core system)
        load = String.to_float(load1)
        min(Float.round(load * 25, 1), 100.0)
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end
  
  # Get RAM usage from memsup
  defp get_ram_usage do
    case :memsup.get_system_memory_data() do
      memory_data when is_list(memory_data) ->
        total = Keyword.get(memory_data, :total_memory, 0)
        free = Keyword.get(memory_data, :free_memory, 0)
        
        if total > 0 do
          used = total - free
          Float.round(used / total * 100, 1)
        else
          0.0
        end
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end
  
  # Get disk usage for /mnt/usb
  defp get_disk_usage do
    disk_path = "/mnt/usb"
    
    case :disksup.get_disk_data() do
      disk_data when is_list(disk_data) ->
        # Find /mnt/usb or root partition
        case Enum.find(disk_data, fn {path, _, _} -> 
          String.starts_with?(to_string(path), disk_path) or to_string(path) == "/"
        end) do
          {_, _total_kb, percent} -> 
            percent
          nil -> 
            # Fallback: use df command
            get_disk_usage_from_df(disk_path)
        end
      _ -> get_disk_usage_from_df(disk_path)
    end
  rescue
    _ -> get_disk_usage_from_df("/")
  end
  
  defp get_disk_usage_from_df(path) do
    try do
      {output, 0} = System.cmd("df", [path, "--output=pcent"], stderr_to_stdout: true)
      output
      |> String.split("\n")
      |> Enum.at(1, "0%")
      |> String.trim()
      |> String.replace("%", "")
      |> String.to_integer()
    rescue
      _ -> 0
    catch
      _, _ -> 0
    end
  end
end
