# CVR - Cloud Video Recorder

Hệ thống ghi hình mạng (NVR - Network Video Recorder) được xây dựng bằng Elixir sử dụng [Membrane Framework](https://github.com/membraneframework)

![CVR dashboard](/screenshots/cvr.png)

## Mục Lục
- [CVR - Cloud Video Recorder](#cvr---cloud-video-recorder)
  - [Yêu Cầu Hệ Thống](#yêu-cầu-hệ-thống)
  - [Cài Đặt và Chạy](#cài-đặt-và-chạy)
    - [Docker (Khuyến nghị)](#docker-khuyến-nghị)
    - [Local Development](#local-development)
  - [Biến Môi Trường](#biến-môi-trường)
  - [WebRTC](#webrtc)
  - [Hỗ Trợ HEVC (H265)](#hỗ-trợ-hevc-h265)
  - [Tính Năng](#tính-năng)
  - [Cấu Trúc Dự Án](#cấu-trúc-dự-án)

## Yêu Cầu Hệ Thống

| Thành phần | Phiên bản |
|------------|-----------|
| Elixir | 1.18+ |
| Erlang/OTP | 27+ |
| Node.js | 18+ |
| FFmpeg | 7.0+ |

> **Lưu ý:** Nếu sử dụng Docker, không cần cài đặt các dependencies trên.

## Cài Đặt và Chạy

### Docker (Khuyến nghị)

**Build image:**
```bash
docker build -t cvr:latest .
```

**Chạy container:**
```bash
docker run --rm -it -p 4000:4000 cvr:latest
```

**Với biến môi trường tùy chỉnh:**
```bash
docker run --rm -it -p 4000:4000 \
  -e CVR_ADMIN_USERNAME=admin@example.com \
  -e CVR_ADMIN_PASSWORD=MySecurePass123 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 32) \
  cvr:latest
```

**Docker Compose:**
```bash
cd docker
docker-compose up -d
```

**Truy cập:** http://localhost:4000

**Tài khoản mặc định:**
- Email: `admin@localhost`
- Password: `P@ssw0rd`

---

### Local Development
#### 1. Cài đặt gói hổ trợ (Debian/Ubuntu/WSL)

```bash
sudo apt update
sudo apt install build-essential autoconf libssl-dev libncurses-dev g++ unzip curl wget git libsrtp2-dev inotify-tools
```

#### 2. Cài đặt Elixir 1.18 (Debian/Ubuntu/WSL)  

**Sử dụng asdf:**
```bash
# Cài asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.bashrc

# Cài Erlang và Elixir
asdf plugin add erlang
asdf plugin add elixir

asdf install erlang 27.0
asdf install elixir 1.18.3

# Kiểm tra
elixir --version
```

#### 2. Cài đặt FFmpeg & Gstreamer

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavdevice-dev gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-alsa gstreamer1.0-pulseaudio gstreamer1.0-x gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-vaapi libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-rtsp

# Debian 12 Radxa 5+ add install 
sudo apt-get install librga-dev librga2 gstreamer1.0-rockchip 

# Kiểm tra
ffmpeg -version
gst-inspect-1.0
```

#### 3. Cài đặt dependencies

```bash
# Video processor
cd video_processor
mix deps.get
mix compile

# UI
cd ../ui
sudo apt install npm
mix deps.get
mix assets.setup
mix ecto.migrate
```

#### 4. Chạy development server

```bash
cd ui
pkill -f "gst-launch"
mix phx.server
```

**Truy cập:** http://localhost:4000

---

### Linux Arm/v7

Build trực tiếp trên thiết bị:
```bash
docker build -t cvr:latest -f Dockerfile .
```

### Debian Package

```bash
# Cài đặt
sudo dpkg -i cvr_<version>_amd64.deb

# Khởi động
sudo systemctl start cvr.service

# Tự động chạy khi boot
sudo systemctl enable cvr.service

# Gỡ cài đặt
sudo systemctl stop cvr.service
sudo systemctl disable cvr.service
sudo dpkg -P cvr
```

## Biến Môi Trường

| Biến | Mô tả | Mặc định |
|------|-------|----------|
| `DATABASE_PATH` | Đường dẫn database SQLite | `/var/lib/cvr/cvr.db` |
| `CVR_HLS_DIRECTORY` | Thư mục lưu HLS playlists | `/tmp/hls` |
| `CVR_ADMIN_USERNAME` | Email tài khoản admin | `admin@localhost` |
| `CVR_ADMIN_PASSWORD` | Mật khẩu admin | `P@ssw0rd` |
| `CVR_DOWNLOAD_DIR` | Thư mục tạm cho video tải về | `/tmp/cvr_downloads` |
| `SECRET_KEY_BASE` | Khóa 64 byte cho mã hóa cookies | - |
| `CVR_URL` | URL base của ứng dụng | `http://localhost:4000` |
| `CVR_HTTP_PORT` | Cổng HTTP | `4000` |
| `CVR_ENABLE_HTTPS` | Bật HTTPS | `false` |
| `CVR_HTTPS_PORT` | Cổng HTTPS | `443` |
| `CVR_SSL_KEY_PATH` | Đường dẫn SSL key | - |
| `CVR_SSL_CERT_PATH` | Đường dẫn SSL certificate | - |
| `CVR_JSON_LOGGER` | Bật JSON logging | `true` |
| `CVR_CORS_ALLOWED_ORIGINS` | Danh sách origins cho CORS | `*` |

## WebRTC

### Cấu Hình

| Biến | Mô tả |
|------|-------|
| `CVR_ICE_SERVERS` | ICE/TURN servers (JSON). Mặc định: `[{"urls":"stun:stun.l.google.com:19302"}]` |

### Truy Cập

```
http://localhost:4000/webrtc/{device_id}
```

### Nhúng

```html
<iframe width="640" height="480" 
        src="http://localhost:4000/webrtc/device_id?access_token=token" 
        title="cvr" allowfullscreen></iframe>
```

> **Lưu ý:** `access_token` sẽ hết hạn và cần được cập nhật.

## Hỗ Trợ HEVC (H265)

H265 là chuẩn mã hóa hiệu quả hơn H264 với bitrate thấp hơn 50% ở cùng chất lượng. Nhiều camera IP hiện đại hỗ trợ H265.

Khi sử dụng CVR để ghi H265:
- Không thực hiện transcoding
- Streaming HLS/WebRTC sẽ là H265
- Khả năng xem phụ thuộc vào trình duyệt (hỗ trợ còn hạn chế)

## Tính Năng

### Thiết Bị Đầu Vào
- ✅ IP Camera
- ✅ RTSP stream
- ✅ Tải lên video
- ⏳ USB / Webcam
- ⏳ Raspberry Pi Camera

### Ghi Hình
- ✅ Main stream
- ✅ Sub-stream

### Phát Hiện Thiết Bị
- ✅ ONVIF discovery

### Codec Video
- ✅ H264
- ✅ H265

### Streaming
- ✅ HLS
- ✅ WebRTC
- ⏳ Webm
- ⏳ RTSP
- ⏳ RTMP

### Tích Hợp
- ✅ Unix-domain Socket
- ✅ REST API & Documentation
- ⏳ Web Hooks

### Tính Năng Khác
- ✅ Hỗ trợ nhiều camera cùng lúc
- ✅ Chụp ảnh snapshot
- ✅ Tải video với thời lượng tùy ý
- ✅ Thống kê stream
- ✅ HTTPS
- ⏳ Hỗ trợ âm thanh
- ⏳ Thu thập metrics
- ⏳ Machine learning trên video
- ⏳ Đồng bộ lên cloud

## Cấu Trúc Dự Án

Dự án theo kiểu **poncho**, gồm các thành phần:

| Thư mục | Mô tả |
|---------|-------|
| `video_processor` | NIF app xử lý video: encoding, decoding, processing |
| `ui` | Logic chính và giao diện Phoenix LiveView |
| `nerves_fw` | Firmware cho thiết bị nhúng (Raspberry Pi) |
| `vendor` | Các dependencies nội bộ |

---

## Kiến Trúc Hệ Thống

### Tổng Quan

TProNVR sử dụng kiến trúc **Hybrid Pipeline** kết hợp FFmpeg + GStreamer + ZLMediaKit:

- **FFmpeg**: RTSP source (tương thích nhiều camera, đặc biệt Dahua/Tapo)
- **GStreamer**: Hardware-accelerated decode/encode, recording (MP4), RTSP push
- **ZLMediaKit**: RTSP proxy trung gian → HLS cho live view + RTSP cho CVEDIX AI
- **Membrane**: HLS playback cho video đã ghi (recorded playback)

```
Camera (RTSP)
    │
    ├── main_stream ──► FFmpeg ──pipe──► GStreamer (HW decode/encode)
    │                                        │
    │                                   ┌────┴────┐
    │                                   ▼         ▼
    │                           rtspclientsink  splitmuxsink
    │                           (main_stream)   (Recording)
    │                                │               │
    │                                ▼               ▼
    │                           ZLMediaKit      Storage (MP4)
    │                           live/{id}       /data/nvr/{id}/
    │
    └── sub_stream ──► FFmpeg push (ZLMediaKit.Stream)
                            │
                            ▼
                       ZLMediaKit
                       live/{id}_sub
```

### ZLMediaKit Integration

ZLMediaKit chạy như native process, nhận RTSP push liên tục từ pipeline:

| Stream | Push Method | ZLMediaKit Key | HLS URL | RTSP URL |
|--------|-------------|----------------|---------|----------|
| **Main** | GStreamer `rtspclientsink` | `live/{id}` | `http://localhost:8080/live/{id}/hls.m3u8` | `rtsp://localhost:8554/live/{id}` |
| **Sub** | FFmpeg via `ZLMediaKit.Stream` | `live/{id}_sub` | `http://localhost:8080/live/{id}_sub/hls.m3u8` | `rtsp://localhost:8554/live/{id}_sub` |

**Config:**
```elixir
# config/config.exs
config :tpro_nvr,
  zlmediakit: [
    host: "localhost",
    rtsp_port: 8554,
    http_port: 8080,
    enabled: true
  ]
```

### Live View vs Playback

| Chế độ | Nguồn | Cơ chế |
|--------|-------|--------|
| **Live View** | ZLMediaKit HLS | Controller 302 redirect → `http://zlm:8080/live/{id}/hls.m3u8` |
| **Playback** | Membrane HlsPlayback | Đọc MP4 từ storage → Membrane sinh HLS segments |

Khi chuyển segment playback, `HlsStreamingMonitor` tự động stop pipeline cũ trước khi start mới.

### CVEDIX AI Analytics

CVEDIX sử dụng ZLMediaKit RTSP làm input (luôn sẵn sàng vì push always-on):

```
ZLMediaKit (rtsp://localhost:8554/live/{device_id})
    │
    ▼
CVEDIX SecuRT Instance → detection events → TProNVR Events DB
```

### GStreamer Pipeline Chi Tiết

```
FFmpeg (RTSP source)                         ZLMediaKit
 -rtsp_transport tcp                              ▲
 -c:v copy -an -f mpegts pipe:1                   │
        │                                         │
        ▼                                         │
 GStreamer Pipeline:                               │
 fdsrc → tsdemux → h264parse                      │
 → mppvideodec (HW decode)                        │
 → tee (raw_tee)                                  │
    ├── mpph264enc → h264parse                     │
    │   → tee (stream_tee)                         │
    │      └── rtspclientsink ─────────────────────┘
    │          rtsp://zlm:8554/live/{device_id}
    │
    └── splitmuxsink (recording)
        {timestamp}_%05d.mp4
```

### Hardware Acceleration

| Platform | Decoder | Encoder H.264 | Detection |
|----------|---------|---------------|-----------|
| **Rockchip RK3588** | `mppvideodec` | `mpph264enc` | Auto |
| **Intel/AMD** | `vaapidecodebin` | `vaapih264enc` | Auto |
| **NVIDIA** | `nvdec` | `nvh264enc` | Auto |
| **Software** | `decodebin3` | `x264enc` | Fallback |

### Technology Stack

| Layer | Technology |
|-------|------------|
| **Language** | Elixir 1.18+, Erlang/OTP 27+ |
| **Web Framework** | Phoenix 1.7, LiveView |
| **Live Streaming** | ZLMediaKit (RTSP proxy → HLS/FLV/WebRTC) |
| **Recording** | GStreamer `splitmuxsink` (H.264 MP4) |
| **Playback** | Membrane `HlsPlayback` |
| **Video Ingestion** | FFmpeg + GStreamer (HW decode/encode) |
| **AI Analytics** | CVEDIX SecuRT (via ZLMediaKit RTSP) |
| **Database** | SQLite (Ecto + Exqlite) |
| **Frontend** | Alpine.js, Vue.js, hls.js |
| **Hardware Accel** | Rockchip MPP, VAAPI, NVENC (auto-detect) |


## Build & Deploy

### Development Build

```bash
# 1. Clone repository
git clone https://github.com/your-org/cvr.git
cd cvr

# 2. Install dependencies
cd ui
mix deps.get
mix assets.setup

# 3. Setup database
mix ecto.setup

# 4. Run development server
mix phx.server

# Access: http://localhost:4000
```

### Production Build

```bash
# 1. Set environment
export MIX_ENV=prod
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# 2. Install dependencies
mix deps.get --only prod

# 3. Compile assets
mix assets.deploy

# 4. Build release
mix release

# 5. Run
_build/prod/rel/tpro_nvr/bin/tpro_nvr start
```

### Systemd Service

```ini
# /etc/systemd/system/cvr.service
[Unit]
Description=CVR Video Recorder
After=network.target

[Service]
Type=simple
User=cvr
Group=cvr
WorkingDirectory=/opt/cvr
Environment=MIX_ENV=prod
Environment=SECRET_KEY_BASE=your_secret_key
Environment=DATABASE_PATH=/var/lib/cvr/cvr.db
ExecStart=/opt/cvr/_build/prod/rel/tpro_nvr/bin/tpro_nvr start
ExecStop=/opt/cvr/_build/prod/rel/tpro_nvr/bin/tpro_nvr stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Storage Structure

```
/mnt/usb/cvr/                        # Base storage
├── {device_id}/
│   ├── hi_quality/                  # Main stream recordings
│   │   └── {YYYY}/{MM}/{DD}/{HH}/
│   │       └── {timestamp}.mp4
│   └── low_quality/                 # Sub stream recordings
│       └── {YYYY}/{MM}/{DD}/{HH}/
│           └── {timestamp}.mp4
│
/tmp/hls/                            # HLS segments (ephemeral)
├── {device_id}/
│   ├── index.m3u8
│   └── segment*.ts
```

---

**Phát triển bởi CVEDIX** 🎥

