defmodule TProNVR.HardwareInfo do
  @moduledoc """
  Hardware information provider using the hwinfo C++ CLI wrapper.
  Caches the result as hardware does not change at runtime.
  """
  use GenServer
  require Logger

  @cache_key :hardware_info_cache

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_info do
    case :ets.lookup(@cache_key, :data) do
      [{:data, info}] -> info
      [] -> GenServer.call(__MODULE__, :fetch_info, 15_000)
    end
  end

  @impl true
  def init(_) do
    :ets.new(@cache_key, [:set, :named_table, :public, read_concurrency: true])

    # Process asynchronously to not block application startup
    send(self(), :load_data)

    {:ok, %{}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    data = fetch_hardware_info()
    :ets.insert(@cache_key, {:data, data})
    {:noreply, state}
  end

  @impl true
  def handle_call(:fetch_info, _from, state) do
    data = fetch_hardware_info()
    :ets.insert(@cache_key, {:data, data})
    {:reply, data, state}
  end

  @impl true
  def handle_info(:load_data, state) do
    data = fetch_hardware_info()
    :ets.insert(@cache_key, {:data, data})
    {:noreply, state}
  end

  defp fetch_hardware_info do
    cli_path = Application.app_dir(:tpro_nvr, "priv/bin/hwinfo_cli")

    if File.exists?(cli_path) do
      case System.cmd(cli_path, [], stderr_to_stdout: true) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, parsed} ->
              parsed

            {:error, error} ->
              Logger.error("Failed to parse hwinfo JSON output: #{inspect(error)}")
              fallback_info()
          end

        {output, exit_code} ->
          Logger.error("hwinfo CLI failed with exit code #{exit_code}: #{output}")
          fallback_info()
      end
    else
      Logger.warning("hwinfo CLI not found at \#{cli_path}. Using fallback info.")
      fallback_info()
    end
  end

  defp fallback_info do
    %{
      "os" => %{
        "name" => "Linux (Fallback)",
        "architecture" => "x86_64"
      },
      "cpu" => [],
      "gpu" => [],
      "ram" => [],
      "disk" => [],
      "battery" => [],
      "mainboard" => %{},
      "fallback" => true
    }
  end
end
