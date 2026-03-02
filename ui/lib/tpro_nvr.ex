defmodule TProNVR do
  @moduledoc false

  require Logger

  import TProNVR.Utils

  alias TProNVR.Accounts

  @first_name "Admin"
  @last_name "Admin"

  @doc """
  Start the main pipeline
  """
  def start do
    if Application.get_env(:tpro_nvr, :env) != :test do
      create_directories()
      create_admin_user()
      TProNVR.Devices.start_all()
      # Start recording watchers for all devices to sync recordings to database
      start_all_watchers()
    end
  end

  # Start RecordingWatcher for all devices to auto-sync recordings to database
  defp start_all_watchers do
    Logger.info("[TProNVR] Starting recording watchers for all devices...")
    
    # Small delay to ensure Supervisor is ready
    Process.sleep(1000)
    
    devices = TProNVR.Devices.list()
    Logger.info("[TProNVR] Found #{length(devices)} devices to start watchers for")
    
    Enum.each(devices, fn device ->
      case TProNVR.Gst.Supervisor.start_watcher(device) do
        {:ok, pid} ->
          Logger.info("[TProNVR] ✅ Started RecordingWatcher for device: #{device.id}, PID: #{inspect(pid)}")
        {:error, {:already_started, pid}} ->
          Logger.info("[TProNVR] Watcher already running for #{device.id}: #{inspect(pid)}")
        {:error, reason} ->
          Logger.error("[TProNVR] ❌ Failed to start watcher for #{device.id}: #{inspect(reason)}")
      end
    end)
    
    Logger.info("[TProNVR] Recording watchers startup complete")
  end

  # create recording & HLS directories
  defp create_directories do
    File.mkdir_p(hls_dir())
    File.mkdir_p(unix_socket_dir())
  end

  defp create_admin_user do
    # if no user create an admin
    if Accounts.count_users() == 0 do
      username = Application.get_env(:tpro_nvr, :admin_username)
      password = Application.get_env(:tpro_nvr, :admin_password)

      with {:error, changeset} <-
             Accounts.register_user(%{
               email: username,
               password: password,
               role: :admin,
               first_name: @first_name,
               last_name: @last_name
             }) do
        Logger.error("""
        Could not create admin user, exiting app...
        #{inspect(changeset)}
        """)

        System.halt(:abort)
      end
    end
  end
end
