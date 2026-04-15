defmodule TProNVR.CVEDIX.SSEAutoStarter do
  @moduledoc """
  Worker that automatically starts SSE consumers for running CVEDIX instances.
  Runs at application startup to connect to all active instances.
  """

  use GenServer
  require Logger

  alias TProNVR.CVEDIX.{Client, SSEConsumer, CvedixInstance}
  alias TProNVR.Repo

  @startup_delay 5_000  # Wait 5 seconds after startup
  @retry_delay 10_000   # Retry every 10 seconds
  @max_retries 3        # Maximum retry attempts

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule startup check after a delay to let the app fully initialize
    Process.send_after(self(), :check_and_start, @startup_delay)
    {:ok, %{started_instances: [], retry_count: 0}}
  end

  @impl true
  def handle_info(:check_and_start, state) do
    Logger.info("SSE AutoStarter: Checking for running CVEDIX instances (attempt #{state.retry_count + 1})...")
    
    started = start_sse_for_running_instances()
    
    Logger.info("SSE AutoStarter: Started #{length(started)} SSE consumers")
    
    # Check if there are DB instances that should have SSE consumers but don't yet
    db_instances = Repo.all(CvedixInstance)
    pending_count = length(db_instances) - length(started ++ state.started_instances)
    
    new_state = %{state | 
      started_instances: Enum.uniq(started ++ state.started_instances),
      retry_count: state.retry_count + 1
    }
    
    # Retry if there are pending instances and we haven't exceeded max retries
    if pending_count > 0 and new_state.retry_count < @max_retries do
      Logger.info("SSE AutoStarter: #{pending_count} instance(s) pending, scheduling retry ##{new_state.retry_count + 1} in #{div(@retry_delay, 1000)}s")
      Process.send_after(self(), :check_and_start, @retry_delay)
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:start_sse_for_instance, instance_id, device_id}, state) do
    case SSEConsumer.start_consumer(instance_id, device_id) do
      {:ok, _pid} ->
        Logger.info("Started SSE consumer for instance #{instance_id}")
        {:noreply, %{state | started_instances: [instance_id | state.started_instances]}}
      {:error, {:already_started, _pid}} ->
        {:noreply, state}
      {:error, reason} ->
        Logger.warning("Failed to start SSE consumer for #{instance_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @doc """
  Manually trigger SSE consumer start for a specific instance.
  Called when an instance becomes running.
  """
  def start_for_instance(instance_id, device_id \\ nil) do
    Logger.info("[SSE AutoStarter] Request to start SSE consumer for instance: #{instance_id}")
    GenServer.cast(__MODULE__, {:start_for_instance, instance_id, device_id})
  end

  @doc """
  Get status of all SSE consumers.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def handle_call(:status, _from, state) do
    running_consumers = 
      Registry.select(TProNVR.CVEDIX.SSERegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    
    status = %{
      started_instances: state.started_instances,
      running_consumers: running_consumers,
      consumer_count: length(running_consumers)
    }
    
    {:reply, status, state}
  end

  @impl true
  def handle_cast({:start_for_instance, instance_id, device_id}, state) do
    Logger.info("[SSE AutoStarter] Starting SSE consumer for instance: #{instance_id}")
    
    case SSEConsumer.start_consumer(instance_id, device_id) do
      {:ok, pid} ->
        Logger.info("[SSE AutoStarter] ✅ SSE consumer STARTED for instance #{instance_id} (PID: #{inspect(pid)})")
        {:noreply, %{state | started_instances: [instance_id | state.started_instances]}}
      {:error, {:already_started, pid}} ->
        Logger.info("[SSE AutoStarter] SSE consumer already running for instance #{instance_id} (PID: #{inspect(pid)})")
        {:noreply, state}
      {:error, reason} ->
        Logger.warning("[SSE AutoStarter] ❌ Failed to start SSE consumer for #{instance_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private helpers

  defp start_sse_for_running_instances do
    # Get all CVEDIX instances from database
    db_instances = Repo.all(CvedixInstance)
    
    db_instances
    |> Enum.filter(&instance_running?/1)
    |> Enum.map(fn db_instance ->
      case SSEConsumer.start_consumer(db_instance.instance_id, db_instance.device_id) do
        {:ok, _pid} ->
          Logger.info("SSE AutoStarter: Connected to instance #{db_instance.instance_id}")
          db_instance.instance_id
        {:error, {:already_started, _}} ->
          db_instance.instance_id
        {:error, reason} ->
          Logger.warning("SSE AutoStarter: Failed to connect to #{db_instance.instance_id}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp instance_running?(db_instance) do
    # Check if instance is running via API
    case Client.get("/v1/core/instance/#{db_instance.instance_id}") do
      {:ok, %{"running" => true}} -> true
      {:ok, %{"state" => "running"}} -> true
      _ -> false
    end
  end
end
