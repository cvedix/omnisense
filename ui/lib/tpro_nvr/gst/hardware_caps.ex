defmodule TProNVR.Gst.HardwareCaps do
  @moduledoc """
  GStreamer hardware capability detection.
  
  Automatically detects available hardware acceleration elements:
  - Rockchip MPP (ARM64): mppvideodec, mpph264enc, mpph265enc
  - Intel/AMD VAAPI: vaapidecodebin, vaapih264enc, vaapih265enc  
  - NVIDIA NVENC: nvdec, nvh264enc, nvh265enc
  - Software fallback: decodebin3, x264enc, x265enc
  
  ## Usage
  
      iex> TProNVR.Gst.HardwareCaps.detect()
      %{platform: :rockchip, decoder: "mppvideodec", encoder_h264: "mpph264enc", ...}
      
      iex> TProNVR.Gst.HardwareCaps.get_decoder()
      "mppvideodec"
  """

  use GenServer
  require Logger

  @cache_ttl_ms :timer.hours(1)
  
  # Hardware element definitions by platform
  @rockchip_elements %{
    platform: :rockchip,
    decoder: "mppvideodec",
    encoder_h264: "mpph264enc",
    encoder_h265: "mpph265enc",
    encoder_jpeg: "mppjpegenc",
    decoder_jpeg: "mppjpegdec"
  }
  
  @vaapi_elements %{
    platform: :vaapi,
    decoder: "vaapidecodebin",
    encoder_h264: "vaapih264enc",
    encoder_h265: "vaapih265enc",
    encoder_jpeg: "vaapijpegenc"
  }
  
  @nvidia_elements %{
    platform: :nvidia,
    decoder: "nvdec",
    encoder_h264: "nvh264enc",
    encoder_h265: "nvh265enc",
    encoder_jpeg: nil
  }
  
  @software_elements %{
    platform: :software,
    decoder: "decodebin3",
    encoder_h264: "x264enc tune=zerolatency speed-preset=ultrafast",
    encoder_h265: "x265enc tune=zerolatency speed-preset=ultrafast",
    encoder_jpeg: "jpegenc"
  }

  # ============================================================
  # Public API
  # ============================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Detect hardware capabilities. Returns cached result if available.
  """
  @spec detect() :: map()
  def detect do
    case Process.whereis(__MODULE__) do
      nil -> do_detect()
      _pid -> GenServer.call(__MODULE__, :get_caps)
    end
  end

  @doc """
  Force re-detection of hardware capabilities.
  """
  @spec refresh() :: map()
  def refresh do
    case Process.whereis(__MODULE__) do
      nil -> do_detect()
      _pid -> GenServer.call(__MODULE__, :refresh)
    end
  end

  @doc """
  Get the best available video decoder element.
  """
  @spec get_decoder() :: String.t()
  def get_decoder, do: detect()[:decoder]

  @doc """
  Get the best available H.264 encoder element.
  """
  @spec get_encoder_h264() :: String.t()
  def get_encoder_h264, do: detect()[:encoder_h264]

  @doc """
  Get the best available H.265 encoder element.
  """
  @spec get_encoder_h265() :: String.t()
  def get_encoder_h265, do: detect()[:encoder_h265]

  @doc """
  Get the best available JPEG encoder element.
  """
  @spec get_encoder_jpeg() :: String.t() | nil
  def get_encoder_jpeg, do: detect()[:encoder_jpeg]

  @doc """
  Get the detected platform (:rockchip, :vaapi, :nvidia, :software).
  """
  @spec get_platform() :: atom()
  def get_platform, do: detect()[:platform]

  @doc """
  Check if hardware acceleration is available.
  """
  @spec hardware_available?() :: boolean()
  def hardware_available?, do: detect()[:platform] != :software

  @doc """
  Check if a specific GStreamer element is available.
  """
  @spec element_available?(String.t()) :: boolean()
  def element_available?(element_name) do
    case System.cmd("gst-inspect-1.0", [element_name], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Build optimized decoder pipeline string based on detected hardware.
  Supports automatic codec detection (H.264/H.265).
  """
  @spec build_decoder_pipeline(keyword()) :: String.t()
  def build_decoder_pipeline(_opts \\ []) do
    caps = detect()
    
    case caps[:platform] do
      :rockchip ->
        # MPP decoder handles both H.264 and H.265
        "mppvideodec"
        
      :vaapi ->
        "vaapidecodebin"
        
      :nvidia ->
        # NVIDIA decoder auto-detects codec
        "nvdec"
        
      :software ->
        # decodebin3 auto-selects decoder based on stream
        "decodebin3"
    end
  end

  @doc """
  Build optimized encoder pipeline string based on detected hardware.
  """
  @spec build_encoder_pipeline(atom(), keyword()) :: String.t()
  def build_encoder_pipeline(codec, opts \\ [])
  
  def build_encoder_pipeline(:h264, opts) do
    caps = detect()
    bitrate = Keyword.get(opts, :bitrate, 2000)
    
    case caps[:platform] do
      :rockchip ->
        "mpph264enc bps=#{bitrate * 1000} gop=30"
        
      :vaapi ->
        "vaapih264enc bitrate=#{bitrate} keyframe-period=30"
        
      :nvidia ->
        "nvh264enc bitrate=#{bitrate} gop-size=30 preset=low-latency-hq"
        
      :software ->
        "x264enc tune=zerolatency bitrate=#{bitrate} speed-preset=ultrafast key-int-max=30"
    end
  end

  def build_encoder_pipeline(:h265, opts) do
    caps = detect()
    bitrate = Keyword.get(opts, :bitrate, 2000)
    
    case caps[:platform] do
      :rockchip ->
        "mpph265enc bps=#{bitrate * 1000} gop=30"
        
      :vaapi ->
        "vaapih265enc bitrate=#{bitrate} keyframe-period=30"
        
      :nvidia ->
        "nvh265enc bitrate=#{bitrate} gop-size=30 preset=low-latency-hq"
        
      :software ->
        "x265enc tune=zerolatency bitrate=#{bitrate} speed-preset=ultrafast"
    end
  end

  # ============================================================
  # GenServer Callbacks
  # ============================================================

  @impl true
  def init(_opts) do
    caps = do_detect()
    Logger.info("[HardwareCaps] Detected platform: #{caps[:platform]}")
    Logger.info("[HardwareCaps] Decoder: #{caps[:decoder]}")
    Logger.info("[HardwareCaps] Encoder H264: #{caps[:encoder_h264]}")
    Logger.info("[HardwareCaps] Encoder H265: #{caps[:encoder_h265]}")
    
    state = %{
      caps: caps,
      detected_at: System.monotonic_time(:millisecond)
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_caps, _from, state) do
    # Check if cache is still valid
    now = System.monotonic_time(:millisecond)
    
    if now - state.detected_at > @cache_ttl_ms do
      caps = do_detect()
      {:reply, caps, %{state | caps: caps, detected_at: now}}
    else
      {:reply, state.caps, state}
    end
  end

  @impl true
  def handle_call(:refresh, _from, _state) do
    caps = do_detect()
    Logger.info("[HardwareCaps] Refreshed - Platform: #{caps[:platform]}")
    
    state = %{
      caps: caps,
      detected_at: System.monotonic_time(:millisecond)
    }
    
    {:reply, caps, state}
  end

  # ============================================================
  # Private Functions
  # ============================================================

  defp do_detect do
    cond do
      # Priority 1: Rockchip MPP (best for ARM64 boards)
      rockchip_available?() ->
        Logger.debug("[HardwareCaps] Rockchip MPP detected")
        @rockchip_elements
        
      # Priority 2: Intel/AMD VAAPI
      vaapi_available?() ->
        Logger.debug("[HardwareCaps] VAAPI detected")
        @vaapi_elements
        
      # Priority 3: NVIDIA NVENC
      nvidia_available?() ->
        Logger.debug("[HardwareCaps] NVIDIA NVENC detected")
        @nvidia_elements
        
      # Fallback: Software encoding
      true ->
        Logger.debug("[HardwareCaps] Using software encoding")
        @software_elements
    end
  end

  defp rockchip_available? do
    # Check for Rockchip MPP decoder (primary indicator)
    element_available?("mppvideodec")
  end

  defp vaapi_available? do
    # Check for VAAPI decoder
    element_available?("vaapidecodebin") or element_available?("vaapidecode")
  end

  defp nvidia_available? do
    # Check for NVIDIA decoder
    element_available?("nvdec") or element_available?("nvh264dec")
  end
end
