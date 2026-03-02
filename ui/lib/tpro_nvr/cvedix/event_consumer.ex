defmodule TProNVR.CVEDIX.EventConsumer do
  @moduledoc """
  GenServer to poll CVEDIX-RT events and broadcast to Phoenix PubSub.

  Events are published to the topic "cvedix:events:{instance_id}".
  """

  use GenServer
  require Logger

  alias TProNVR.CVEDIX.Client

  @default_poll_interval 1_000

  # Client API

  @doc """
  Start the event consumer for an instance.
  """
  def start_link(instance_id, opts \\ []) do
    name = via_tuple(instance_id)
    GenServer.start_link(__MODULE__, {instance_id, opts}, name: name)
  end

  @doc """
  Subscribe to events for an instance.
  Starts the consumer if not already running.
  """
  def subscribe(instance_id) do
    case start_consumer(instance_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @doc """
  Unsubscribe from events for an instance.
  Stops the consumer.
  """
  def unsubscribe(instance_id) do
    case Registry.lookup(TProNVR.CVEDIX.Registry, instance_id) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> :ok
    end
  end

  @doc """
  Get the PubSub topic for an instance.
  """
  def topic(instance_id), do: "cvedix:events:#{instance_id}"

  # Server callbacks

  @impl true
  def init({instance_id, opts}) do
    poll_interval = Keyword.get(opts, :poll_interval, get_poll_interval())

    state = %{
      instance_id: instance_id,
      poll_interval: poll_interval,
      consecutive_errors: 0
    }

    # Start polling immediately
    send(self(), :poll)

    Logger.info("CVEDIX EventConsumer started for instance #{instance_id}")
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = fetch_and_broadcast_events(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("CVEDIX EventConsumer stopped for instance #{state.instance_id}: #{inspect(reason)}")
    :ok
  end

  # Private helpers

  defp start_consumer(instance_id) do
    DynamicSupervisor.start_child(
      TProNVR.CVEDIX.EventSupervisor,
      {__MODULE__, instance_id}
    )
  end

  defp fetch_and_broadcast_events(state) do
    case Client.get("/v1/core/instance/#{state.instance_id}/consume_events") do
      {:ok, events} when is_list(events) and events != [] ->
        broadcast_events(state.instance_id, events)
        %{state | consecutive_errors: 0}

      {:ok, _} ->
        # No events or empty response
        %{state | consecutive_errors: 0}

      :ok ->
        # 204 No Content - no events available
        %{state | consecutive_errors: 0}

      {:error, {:http_error, 204, _}} ->
        # No events
        %{state | consecutive_errors: 0}

      {:error, reason} ->
        Logger.warning("Failed to fetch CVEDIX events: #{inspect(reason)}")
        %{state | consecutive_errors: state.consecutive_errors + 1}
    end
  end

  defp broadcast_events(instance_id, events) do
    topic = topic(instance_id)

    Enum.each(events, fn event ->
      parsed_event = parse_event(event)
      Phoenix.PubSub.broadcast(TProNVR.PubSub, topic, {:cvedix_event, parsed_event})

      # Also broadcast to specific event type topic
      if parsed_event.type do
        type_topic = "cvedix:#{parsed_event.type}:#{instance_id}"
        Phoenix.PubSub.broadcast(TProNVR.PubSub, type_topic, {:cvedix_event, parsed_event})
      end
    end)

    Logger.debug("Broadcast #{length(events)} CVEDIX events for instance #{instance_id}")
  end

  defp parse_event(%{"dataType" => data_type, "jsonObject" => json_object}) do
    case Jason.decode(json_object) do
      {:ok, data} ->
        %{
          type: data_type,
          data: data,
          timestamp: DateTime.utc_now()
        }

      {:error, _} ->
        %{
          type: data_type,
          data: %{raw: json_object},
          timestamp: DateTime.utc_now()
        }
    end
  end

  defp parse_event(event) do
    %{
      type: nil,
      data: event,
      timestamp: DateTime.utc_now()
    }
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp via_tuple(instance_id) do
    {:via, Registry, {TProNVR.CVEDIX.Registry, instance_id}}
  end

  defp get_poll_interval do
    Application.get_env(:tpro_nvr, :cvedix, [])[:poll_interval] || @default_poll_interval
  end
end
