# OmniSense - AI NVR (Network Video Recorder)

OmniSense là Hệ thống ghi hình và phân tích video mạng thông minh (AI-infused Network Video Recorder). Lấy cảm hứng từ kiến trúc phân tích thị giác máy tính như NVIDIA Jetson Platform Services, OmniSense tạo ra sự vượt trội nhờ khả năng **hỗ trợ trên mọi phần cứng**, từ thiết bị nhúng (Rockchip, Raspberry Pi), Edge AI (NVIDIA Jetson) cho tới máy chủ x86 (Intel/AMD) với khả năng tự động nhận diện và tận dụng độ trễ cực thấp.

Hệ thống được xây dựng bằng Elixir kết hợp sức mạnh của [Membrane Framework](https://github.com/membraneframework) và một kiến trúc Hybrid Pipeline hiện đại. Điều này cung cấp khả năng quay quét, lưu trữ (VST storage), giám sát streaming thời gian thực với độ phân giải cao và khả năng cắm chạy (plug-and-play) các module xử lý AI mạnh mẽ.

## Tính Năng Nổi Bật (AI NVR Production Features)

Mang trong mình mô hình thiết kế của một hệ thống NVR sản xuất thương mại thế hệ mới, OmniSense cung cấp các dịch vụ nền tảng (foundation services) mạnh mẽ:

- 🧠 **Real-time Perception & Analytics**: Tích hợp luồng phân tích video AI theo thời gian thực (DeepStream / CVEDIX AI / RKNN). Hỗ trợ định nghĩa trước các vùng quan tâm (Region of Interest - ROI), hàng rào ảo cảnh báo (Tripwire/Line crossing), và mô hình nhận diện hành vi (Behaviors API).
- 🛡️ **An ninh & Giám sát hệ thống (Monitoring)**: Đi kèm các module watchdog mạnh mẽ để báo cáo từ xa dữ liệu giám sát tài nguyên thiết bị (CPU, RAM, GPU, Storage).
- 📷 **Camera Discovery & VST (Video Storage Toolkit)**: Khám phá và quản lý vòng đời camera tự động (ONVIF discovery). Tối ưu việc nạp luồng, quản lý không gian lưu trữ và tái phát nội dung stream cực mượt mà.
- ⚡ **Khả năng tăng tốc phần cứng thông minh (Hỗ trợ mọi phần cứng)**:
  - **NVIDIA / Jetson**: Tận dụng triệt để NVENC/NVDEC và DLA để tối ưu hóa inference.
  - **Intel/AMD**: Sử dụng thư viện VAAPI cho việc giải mã/mã hóa nhanh mức lõi (hardware level).
  - **Rockchip (RK3588, v.v.)**: Sử dụng Rockchip MPP (mppvideodec, mpph264enc).
  - **Mặc định**: Tự động fallback xuống năng lực Software/CPU Decoding bằng các bộ thư viện đa cấu trúc đảm bảo AI NVR của bạn luôn có thể chạy trên mọi nền tảng.
- 🚀 **Hiệu suất Streaming Edge-to-Cloud**: Tích hợp ZLMediaKit và WebRTC để phân phối luồng HLS/RTSP/WebRTC với độ trễ từ camera tới client có thể dưới 1 giây.

---

## Mục Lục
- [Yêu Cầu Hệ Thống](#yêu-cầu-hệ-thống)
- [Cài Đặt và Chạy](#cài-đặt-và-chạy)
- [Biến Môi Trường](#biến-môi-trường)
- [WebRTC](#webrtc)
- [Hỗ Trợ HEVC (H265)](#hỗ-trợ-hevc-h265)
- [Tính Năng](#tính-năng)
- [Kiến Trúc Hệ Thống](#kiến-trúc-hệ-thống)

---

## Yêu Cầu Hệ Thống

| Thành phần | Phiên bản |
|------------|-----------|
| Elixir | 1.18+ |
| Erlang/OTP | 27+ |
| Node.js | 18+ |
| FFmpeg | 7.0+ |

> **Lưu ý:** Nếu sử dụng qua Docker, các thành phần phần mềm này sẽ được đóng gói sẵn tự động.

## Cài Đặt và Chạy

### Docker (Khuyến nghị)

**Build image:**
```bash
docker build -t omnisense:latest .
```

**Chạy container độc lập:**
```bash
docker run --rm -it -p 4000:4000 omnisense:latest
```

**Với biến môi trường tùy chỉnh:**
```bash
docker run --rm -it -p 4000:4000 \
  -e CVR_ADMIN_USERNAME=admin@example.com \
  -e CVR_ADMIN_PASSWORD=MySecurePass123 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 32) \
  omnisense:latest
```

**Docker Compose (Quản lý đa vi dịch vụ AI NVR):**
Mọi thành phần của OmniSense được ghép lại qua Compose đảm bảo triển khai hệ thống an ninh tin cậy:
```bash
cd docker
docker-compose up -d
```

**Truy cập UI:** http://localhost:4000

**Tài khoản đăng nhập hệ thống mặc định:**
- Email: `admin@localhost`
- Password: `P@ssw0rd`

---

### Local Development (Phát triển cục bộ)
#### 1. Cài đặt thư viện phát triển lõi (Debian/Ubuntu/WSL)

```bash
sudo apt update
sudo apt install build-essential autoconf libssl-dev libncurses-dev g++ unzip curl wget git libsrtp2-dev inotify-tools
```

#### 2. Cài đặt Elixir 1.18 (Môi trường Erlang/OTP)  

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

# Kiểm tra version
elixir --version
```

#### 3. Cài đặt FFmpeg & Gstreamer (Xử lý âm thanh/hình ảnh đa nền tảng)

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavdevice-dev gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-alsa gstreamer1.0-pulseaudio gstreamer1.0-x gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-vaapi libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-rtsp

# Với SBC như Radxa 5+ (Debian 12+), cài thêm plugin phần cứng
sudo apt-get install librga-dev librga2 gstreamer1.0-rockchip 

# Kiểm tra
ffmpeg -version
gst-inspect-1.0
```

#### 4. Kích hoạt Backend & Frontend dependencies

```bash
# Module bộ vi xử lý Video (C-node)
cd video_processor
mix deps.get
mix compile

# Lớp UI tương tác
cd ../ui
sudo apt install npm
mix deps.get
mix assets.setup
mix ecto.migrate
```

#### 5. Chạy Local Server

```bash
cd ui
pkill -f "gst-launch"
mix phx.server
```

**Truy cập tại:** http://localhost:4000

---

### Linux Arm/v7 & Triển khai vào Edge Devices

Với tính linh hoạt từ thiết kế Multi-platform, OmniSense hỗ trợ build Docker Image trực tiếp cho ARMv7 hoặc ARM64 từ Edge node:
```bash
docker build -t omnisense:latest -f Dockerfile .
```

### Triển khai hệ thống gốc cấp Hệ điều hành (Debian Package)

Gói package tối ưu giúp OmniSense chạy dưới dạng background service trên Linux:
```bash
# Cài đặt file .deb
sudo dpkg -i omnisense_<version>_amd64.deb

# Khởi chạy dịch vụ systemd
sudo systemctl start omnisense.service

# Tự động giám sát/hiện thực hóa dịch vụ lên tại boot
sudo systemctl enable omnisense.service

# Gỡ bỏ hệ thống hoàn toàn khỏi thiết bị
sudo systemctl stop omnisense.service
sudo systemctl disable omnisense.service
sudo dpkg -P omnisense
```

## Biến Môi Trường Cơ Bản

Hệ thống cho phép tinh chỉnh luồng bằng các Biến Môi trường tại file `docker-compose.yml` hoặc profile hệ điều hành (os-level init parameters):

| Biến | Mô tả | Mặc định |
|------|-------|----------|
| `DATABASE_PATH` | Đường dẫn Data layer SQLite | `/var/lib/cvr/cvr.db` |
| `CVR_HLS_DIRECTORY` | Phân vùng buffer playlist HLS (Nên lưu `/tmp` cho luồng RAM) | `/tmp/hls` |
| `CVR_ADMIN_USERNAME` | Email tài khoản quản lý gốc (admin user) | `admin@localhost` |
| `CVR_ADMIN_PASSWORD` | Mật khẩu truy cập | `P@ssw0rd` |
| `CVR_DOWNLOAD_DIR` | Thư mục dump export video tạm | `/tmp/cvr_downloads` |
| `SECRET_KEY_BASE` | Khóa mã hóa session Web/Phoenix Framework (độ dài 64 bytes) | - |
| `CVR_HTTP_PORT` | Cổng Public cho Http | `4000` |
| `CVR_JSON_LOGGER` | Kết nối dạng JSON log cho ElasticSearch/Kibana Stack | `true` |

## WebRTC

WebRTC là tiêu chuẩn cao nhất cho ứng dụng NVR yêu cầu tính tương tác thời gian thực thấp-độ-trễ (low-latency interaction) < 1s.

### Cấu Hình ICE/TURN Server

| Biến | Mô tả |
|------|-------|
| `CVR_ICE_SERVERS` | Khai báo máy chủ trung chuyển (STUN/TURN) định dạng JSON. Mặc định: `[{"urls":"stun:stun.l.google.com:19302"}]` |

### Truy Cập Nhanh Trình Duyệt

```
http://localhost:4000/webrtc/{device_id}
```

### Nhúng Vào Frontend Command Center / App Phụ

```html
<iframe width="640" height="480" 
        src="http://localhost:4000/webrtc/device_id?access_token=token" 
        title="OmniSense NVR Live View" allowfullscreen></iframe>
```

> **Ghi chú bảo mật:** `access_token` sẽ hết hạn theo phiên và cần triển khai luồng refresh token ở Controller.

## Hỗ Trợ HEVC (H265) Ở Cấp Độ Edge

H265/HEVC là công nghệ ghi hình mật độ cao rất phổ biến trên các hệ thống NVR thương mại tân tiến, tối ưu băng thông và không gian lưu trữ đến >50% so với thế hệ cũ.

**OmniSense quản lý quy trình phân tích H265 cực kỳ thông minh:**
- Nhận diện luồng gốc H265, lưu file Video không tiến hành "transcoding" (phân giải - mã hóa lại) giúp GPU/CPU thừa sức tập trung hoàn toàn vào inference mô hình Trí tuệ Nhân tạo thông minh (Analytics workloads).
- Khả năng forward toàn bộ luồng H265 native thông quan hệ thống Storage VST về trực tiếp trên WebRTC/HLS. Lưu ý tính năng xem trực tiếp luồng HEVC HLS Web yêu cầu sự tương thích giải mã phần cứng từ phía trình duyệt (vd: Safari).

## Danh Sách Các Chức Năng Cốt Lõi Đặc Biệt

- ✅ Nhập liệu từ phần lớn thiết bị bảo mật hiện tại (IP Camera, RTSP proxy, Bulk uploads video).
- ✅ Hệ thống NVR Dual-Stream hiện đại: Nhập cả Stream chất lượng siêu cao vào Storage riêng (High-res backup) đồng thời lấy stream độ phân giải thấp để đẩy đi xử lý AI và render lên UI nhẹ nhàng.
- ✅ Autodiscovery chuẩn an ninh ONVIF cho cơ chế Plug-And-Play tự động quét và load cấu hình camera.
- ✅ Xuất luồng Native tới các hệ thống Analytics Server/Cloud qua Unix-domain Socket hay RTSP Sink. Cung cấp Data-metadata REST APIs / JSON format events.
- ⏳ Đồng bộ Cloud cho backup dự phòng an toàn từ xa và hệ thống cảnh báo đa điểm tập trung (Web Hooks).

## Kiến Trúc Hệ Thống (Hiệu Năng & AI-Ready)

### Tổng Quan Data Pipeline (Hybrid Pipeline)

OmniSense sử dụng cấu trúc Hybrid Pipeline tiên tiến nhất với khả năng linh hoạt cho xử lý cả FFmpeg và sức mạnh luồng Video GStreamer (kết nối proxy lõi C/C++):

- **Phần mềm quản lý In-gest & Forwarding**: Xử lý logic vòng đời luồng bằng API qua FFmpeg.
- **Node tăng tốc phần cứng GStreamer Pipeline**: Nhận luồng gốc, HW Decoder & HW Encoder để xuất luồng ghi MP4 và truyền đồng thời luồng RAW qua buffer vào AI node mà không ảnh hưởng băng thông gốc.
- **Media Engine lõi ZLMediaKit**: Node trung chuyển và phiên bản Streaming Edge nhận dạng luồng chuyển đổi các giao thức phổ biến thành HLS / WebRTC thời gian thực xuất tới Trình quản trị frontend.

```text
Camera Network (RTSP)
    │
    ├── VST Main Stream ──► FFmpeg Buffer ──pipe──► GStreamer TPro Component (HW Accelerated Decoder/Encoder)
    │                                                    │
    │                                               ┌────┴───────┐
    │                                               ▼            ▼
    │                                      rtspclientsink      splitmuxsink
    │                                      (Stream Proxy)      (NVR Storage MP4)
    │                                            │               │
    │                                            ▼               ▼
    │                                   Core Media Engine     Disk System Storage
    │                                      live/{id}          /data/omnisense_nvr/
    │
    └── VST Sub Stream ──► FFmpeg proxy push stream directly
                                 │
                                 ▼
                          ZLMediaKit
                          live/{id}_sub
```

### Kiến Trúc Plugin Phân Tích (Analytics Engine)

Cấu trúc OmniSense sẵn sàng thiết lập các luồng không gian và thời gian theo cơ chế nhận diện từ DeepStream Perception hay CVEDIX AI:
Luồng được tạo dưới nhánh Proxy sẽ được chuyển tiếp thành Endpoint sẵn sàng để Analytic container lấy vào thông qua kết nối cục bộ.
- Xử lý các phép phân tích theo thời gian thực (Rule-based Line crossing / ROI Polygon).
- Xử lý Object tracking & classification.
- Metadata được trả về JSON Events Dashboard tập trung cho việc giám sát an ninh.

### Sự Đa Dạng Tùy Chỉnh Phần Cứng AI NVR (Hardware Inference)

Sự đặc biệt từ OmniSense đảm bảo mọi hệ thống đều nhận được sự bù đắp tốt từ linh kiện sẵn có:

| Server Hardware | Chipset Decode/Encode | Module AI Xử Lý Analytic Nhận Diện Cảnh Báo |
|----------|---------|---------------|
| **Thiết Bị Cạnh RK3588 (SBC)** | Hỗ trợ Native bằng `mppvideodec` (Rockchip) | RKNN (NPU Accelerator) |
| **Máy Trạm Edge Intel/AMD CPU** | Hỗ trợ Hardware Video qua chuẩn VAAPI | Fallback Software / OpenVINO |
| **Máy Chủ AI NVR NVIDIA (Orin)** | Sức mạnh từ Core `nvdec` chuyên biệt | Tối ưu bằng DeepStream / TensorRT |
| **Môi trường ảo hóa/Generic OS** | Hỗ trợ Software rendering qua `decodebin3` | CPU-based / OpenCV Algorithms |

## Build & Phân Phối Phiên Bản Khép Kín (Production Pipeline)

Biên dịch một phiên bản hoàn chỉnh của NVR OmniSense cho máy chủ nội bộ hoặc triển khai Docker quy mô công nghiệp:

### Production Build Server Nguyên Bản

```bash
# 1. Định hình môi trường
export MIX_ENV=prod
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# 2. Xây dựng modules từ C -> Elixir
mix deps.get --only prod

# 3. Tổng hợp assets
mix assets.deploy

# 4. Trực tiếp Build release không phục thuộc cài đặt
mix release

# 5. Mở hệ thống
_build/prod/rel/omnisense/bin/omnisense start
```

### Tổ Chức Nền Tảng Lưu Trữ (VST Storage Schema Blueprint)

Cấu trúc ổ đĩa hệ thống NVR OmniSense:
```text
/mnt/storage_disk/          # Ổ đĩa Data Volume (Xử lý mã hóa tùy chọn OS)
├── {camera_id}/
│   ├── hi_quality/          # Bản ghi phân giải siêu cao (Evidence Backup)
│   │   └── {Năm}/{Tháng}/{Ngày}/{Giờ}/{Tệp_video}.mp4
│   └── low_quality/         # Bản sub-stream tiết kiệm phục vụ tra cứu lướt dòng thời gian bằng Web (Web Timeline query)
└── tmp_hls_ramdisk/         # Cache Stream Playlist tại RAM
```

---

**Sản phẩm được xây dựng bằng kiến trúc thông minh tự động hóa hướng tới tương lai.**
**Mang khả năng sản xuất đỉnh cao bởi CVEDIX 🎥**.
