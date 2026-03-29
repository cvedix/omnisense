defmodule TProNVRWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:my_sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:file, :line],
        rate_limiting: [max_events: 10, interval: _1_second = 1_000],
        capture_log_messages: false
      }
    })

    children =
      [
        TProNVR.Repo,
        TProNVR.TokenPruner,
        {Phoenix.PubSub, name: TProNVR.PubSub},
        {Finch, name: TProNVR.Finch},
        {Task.Supervisor, name: TProNVR.TaskSupervisor},
        {TProNVR.SystemStatus, []},
        TProNVR.SystemMonitor,
        TProNVR.HardwareInfo,
        {DynamicSupervisor, [name: TProNVR.PipelineSupervisor, strategy: :one_for_one]},
        # Live stream WebSocket/MSE support
        TProNVR.LiveStream.Supervisor,
        # CVEDIX-RT integration
        TProNVR.CVEDIX.Supervisor,
        TProNVRWeb.Telemetry,
        TProNVRWeb.Endpoint,
        TProNVRWeb.PromEx,
        {TProNVRWeb.HlsStreamingMonitor, []},
        {DynamicSupervisor, [name: TProNVR.Hardware.Supervisor, strategy: :one_for_one]},
        {TProNVR.Hardware.SerialPortChecker, []},
        # Recording sync worker - syncs recordings from disk to database every 30s
        TProNVR.Recordings.SyncWorker,
        # Commander Telemetry background worker (NVR Mode)
        TProNVR.CommanderSync.Worker,
        # Commander RTMP Feed Push Orchestrator
        TProNVR.CommanderSync.RTMPWorker,
        Task.child_spec(fn -> TProNVR.start() end)
      ] ++ remote_connector()

    opts = [strategy: :one_for_one, name: TProNVRWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TProNVRWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp remote_connector do
    options = Application.get_env(:tpro_nvr, :remote_server, [])

    if uri = Keyword.get(options, :uri) do
      token = options[:token]
      uri = if token, do: "#{uri}?token=#{token}", else: uri

      [{TProNVR.RemoteConnection, [uri: uri, message_handler: options[:message_handler]]}]
    else
      []
    end
  end
end
