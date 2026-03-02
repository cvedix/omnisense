defmodule TProNVRWeb.API.RecordingController do
  @moduledoc false
  use TProNVRWeb, :controller

  action_fallback TProNVRWeb.API.FallbackController

  import TProNVRWeb.Controller.Helpers

  alias Ecto.Changeset
  alias TProNVR.Recordings

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, Changeset.t()}
  def index(conn, params) do
    device = conn.assigns.device

    with {:ok, params} <- validate_index_req_params(params) do
      params
      |> Map.put(:device_id, device.id)
      |> Recordings.list_runs(params.stream)
      |> Enum.map(&Map.take(&1, [:start_date, :end_date, :active]))
      |> then(&json(conn, &1))
    end
  end

  @spec chunks(Plug.Conn.t(), map) :: Plug.Conn.t()
  def chunks(conn, params) do
    with {:ok, %{stream: stream}} <- validate_chunks_req_params(params),
         {:ok, {recordings, meta}} <- Recordings.list(params, stream) do
      meta =
        Map.take(meta, [
          :current_page,
          :page_size,
          :total_count,
          :total_pages
        ])

      recordings = Enum.map(recordings, &Map.drop(&1, [:device_name, :timezone]))

      json(conn, %{meta: meta, data: recordings})
    end
  end

  @spec blob(Plug.Conn.t(), map) :: Plug.Conn.t()
  def blob(conn, %{"recording_id" => recording_filename} = params) do
    device = conn.assigns.device

    with {:ok, params} <- validate_blob_req_params(params) do
      if recording = Recordings.get(device, params.stream, recording_filename) do
        path = Recordings.recording_path(device, params.stream, recording)
        
        # Check if file actually exists on disk
        if File.exists?(path) do
          content_type = content_type_for_recording(recording_filename)
          send_file_with_range_support(conn, path, content_type)
        else
          # File exists in database but not on disk - may have been renamed or deleted
          not_found(conn)
        end
      else
        not_found(conn)
      end
    end
  end
  
  # Determine correct Content-Type based on file extension
  # GStreamer creates .mkv files, Membrane creates .mp4 files
  defp content_type_for_recording(filename) do
    case Path.extname(filename) do
      ".mkv" -> "video/x-matroska"
      ".mp4" -> "video/mp4"
      ".ts" -> "video/mp2t"
      _ -> "video/mp4"
    end
  end
  
  # Send file with proper Range Request support for video playback
  defp send_file_with_range_support(conn, path, content_type) do
    %{size: file_size} = File.stat!(path)
    
    case get_req_header(conn, "range") do
      ["bytes=" <> range] ->
        # Parse range header (e.g., "0-1023" or "0-" or "-1024")
        {start_pos, end_pos} = parse_range(range, file_size)
        length = end_pos - start_pos + 1
        
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-range", "bytes #{start_pos}-#{end_pos}/#{file_size}")
        |> put_resp_header("content-length", to_string(length))
        |> send_file(206, path, start_pos, length)
        
      _ ->
        # No range requested - send full file with Accept-Ranges header
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-length", to_string(file_size))
        |> send_file(200, path)
    end
  end
  
  defp parse_range(range, file_size) do
    case String.split(range, "-") do
      [start_str, ""] ->
        # "0-" means from start to end
        start_pos = String.to_integer(start_str)
        {start_pos, file_size - 1}
        
      ["", suffix_str] ->
        # "-1024" means last 1024 bytes
        suffix = String.to_integer(suffix_str)
        {max(0, file_size - suffix), file_size - 1}
        
      [start_str, end_str] ->
        start_pos = String.to_integer(start_str)
        end_pos = min(String.to_integer(end_str), file_size - 1)
        {start_pos, end_pos}
    end
  end

  defp validate_index_req_params(params) do
    types = %{
      start_date: :utc_datetime_usec,
      stream: {:parameterized, {Ecto.Enum, Ecto.Enum.init(values: ~w(high low)a)}}
    }

    {%{stream: :high}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end

  defp validate_chunks_req_params(params) do
    types = %{stream: {:parameterized, {Ecto.Enum, Ecto.Enum.init(values: ~w(high low)a)}}}

    {%{stream: :high}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end

  defp validate_blob_req_params(params) do
    types = %{stream: {:parameterized, {Ecto.Enum, Ecto.Enum.init(values: ~w(high low)a)}}}

    {%{stream: :high}, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.apply_action(:create)
  end
end
