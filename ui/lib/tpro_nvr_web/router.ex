defmodule TProNVRWeb.Router do
  use TProNVRWeb, :router

  import TProNVRWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {TProNVRWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json", "jpg", "mp4"]
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :api_require_authenticated_user do
    plug :require_authenticated_user, api: true
  end

  scope "/api", TProNVRWeb do
    pipe_through [:api, :require_webhook_token, TProNVRWeb.Plug.Device]

    post "/devices/:device_id/events", API.EventController, :create
    post "/devices/:device_id/events/lpr", API.EventController, :create_lpr
  end

  scope "/api", TProNVRWeb do
    pipe_through [:api, :api_require_authenticated_user]

    resources "/users", API.UserController, except: [:new, :edit]

    resources "/remote-storages", API.RemoteStorageController, except: [:new, :edit]

    resources "/devices", API.DeviceController, except: [:new, :edit]

    get "/events", API.EventController, :events
    get "/events/lpr", API.EventController, :lpr

    get "/recordings/chunks", API.RecordingController, :chunks

    post "/onvif/discover", API.OnvifController, :discover
    get "/onvif/discover", API.OnvifController, :discover

    scope "/devices/:device_id" do
      pipe_through TProNVRWeb.Plug.Device

      get "/recordings", API.RecordingController, :index
      get "/recordings/:recording_id/blob", API.RecordingController, :blob

      get "/hls/index.m3u8", API.DeviceStreamingController, :hls_stream

      get "/snapshot", API.DeviceStreamingController, :snapshot
      get "/footage", API.DeviceStreamingController, :footage

      get "/bif/:hour", API.DeviceStreamingController, :bif
    end

    # CVEDIX-RT proxy endpoints
    get "/cvedix/instance/:instance_id/frame", API.CVEDIXController, :frame

    get "/system/status", API.SystemStatusController, :status
    get "/system/metrics", API.SystemStatusController, :metrics
  end

  scope "/api", TProNVRWeb do
    pipe_through :api

    post "/users/login", API.UserSessionController, :login

    scope "/devices/:device_id" do
      pipe_through TProNVRWeb.Plug.Device

      get "/hls/:segment_name", API.DeviceStreamingController, :hls_stream_segment
    end
  end

  if Application.compile_env(:tpro_nvr, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TProNVRWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TProNVRWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/login", UserLoginLive, :new
      # live "/users/register", UserRegistrationLive, :new
      live "/users/reset-password", UserForgotPasswordLive, :new
      live "/users/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/users/login", UserSessionController, :create
  end

  scope "/", TProNVRWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home
    get "/webrtc/:device_id", PageController, :webrtc

    import Phoenix.LiveDashboard.Router

    live_dashboard "/live-dashboard",
      metrics: TProNVRWeb.Telemetry,
      additional_pages: [
        "ai-video-analytics": TProNVRWeb.LiveDashboard.CVEDIXPage
      ]

    live_session :require_authenticated_user,
      on_mount: [
        {TProNVRWeb.UserAuth, :ensure_authenticated},
        {TProNVRWeb.Navigation, :set_current_path},
        {TProNVRWeb.SystemMetricsHook, :default},
        {TProNVRWeb.EventNotificationHook, :default}
      ] do
      live "/dashboard", SystemDashboardLive, :index
      live "/emap", EMapLive, :index
      live "/playback", PlaybackLive, :new
      live "/live-view", LiveDashboardLive, :index

      live "/devices", DeviceListLive, :list
      live "/devices/:id/details", DeviceDetailsLive, :show

      live "/recordings", RecordingListLive, :list
      live "/events/generic", GenericEventsLive, :index
      live "/events/lpr", LPREventsListLive, :list
      live "/events/face", FaceEventsListLive, :list
      live "/events/ai-analytics", AnalyticsEventsLive, :index
      live "/events/ai-events", AIEventsLive, :index
      live "/events/ai-heatmap", AIHeatmapLive, :index
      live "/events/ai-tripwire-chart", CrossingChartLive, :index
      live "/events/ai-loitering-report", LoiteringReportLive, :index

      live "/analytics/instances", CVEDIXInstancesLive, :index

      live "/about", AboutLive, :index
      live "/about/hardware", AboutLive, :hardware
      live "/commander-sync", CommanderSyncLive, :index
      live "/commander-sync/logs", CommanderSyncLive, :logs
      live "/commander-sync/rtmp", CommanderSyncLive, :rtmp

      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm-email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TProNVRWeb do
    pipe_through [:browser]

    delete "/users/logout", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TProNVRWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/", TProNVRWeb do
    pipe_through [:browser]

    live_session :admin_routes,
      on_mount: [
        {TProNVRWeb.UserAuth, :ensure_authenticated},
        {TProNVRWeb.UserAuth, :ensure_user_is_admin},
        {TProNVRWeb.Navigation, :set_current_path},
        {TProNVRWeb.SystemMetricsHook, :default}
      ] do
      live "/devices/:id", DeviceLive, :edit

      live "/remote-storages", RemoteStorageListLive, :list
      live "/remote-storages/:id", RemoteStorageLive, :edit

      live "/onvif-discovery", OnvifDiscoveryLive, :onvif_discovery

      live "/users", UserListLive, :list
      live "/users/:id", UserLive, :edit

      live "/storage", StorageLive, :index
    end
  end

  # An ugly solution to extend the TProNVR UI for custom pages/controllers/rest endpoints
  # only when running the nerves image
  if Application.compile_env(:tpro_nvr, :nerves_routes) do
    # nerves live routes, controllers and API endpoints goes here
    scope "/", TProNVR.NervesWeb do
      pipe_through [:browser]

      live_session :nerves_system_settings,
        on_mount: [
          {TProNVRWeb.UserAuth, :ensure_authenticated},
          {TProNVRWeb.UserAuth, :ensure_user_is_admin},
          {TProNVRWeb.Navigation, :set_current_path}
        ] do
        live "/nerves/system-settings", SystemSettingsLive, :index
      end
    end
  end
end
