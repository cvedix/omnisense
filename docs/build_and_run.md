# Hướng Dẫn Build & Run Dự Án OmniSense (AI NVR)

Tài liệu này cung cấp hướng dẫn chi tiết về cách thiết lập, biên dịch và chạy dự án OmniSense trên các nền tảng khác nhau bao gồm môi trường phát triển (Local Development), Docker (Containerization), và môi trường thực tế (Production / Systemd).

---

## 1. Yêu Cầu Hệ Thống (Prerequisites)

Để đảm bảo hệ thống có thể chạy hoặc biên dịch thành công, môi trường của bạn cần tối thiểu:

- **Elixir**: 1.18+
- **Erlang/OTP**: 27+
- **Node.js**: 18+ (Dành cho việc biên dịch frontend/assets)
- **FFmpeg**: 7.0+ (Hoạt động cùng Gstreamer cho xử lý hình ảnh)
- Hệ điều hành khuyến nghị: Ubuntu 22.04 / Debian 12 (Hoặc các bản phân phối Linux tương tự cho WSL/Edge Devices).

*(Lưu ý: Nếu bạn chạy thông qua Docker, các phiên bản phần mềm trên đã được đóng gói sẵn trong Container, bạn chỉ cần một hệ thống có cài đặt Docker).*

---

## 2. Thiết Lập Môi Trường Local Development

Cách thức này dành cho các kỹ sư muốn phát triển tính năng, kiểm thử mã nguồn trực tiếp (Live Reload).

### Bước 2.1: Cài đặt gói hỗ trợ cơ sở (Hệ điều hành)

Cập nhật danh sách gói lệnh và cài đặt các thư viện lõi phục vụ biên dịch:
```bash
sudo apt update
sudo apt install build-essential autoconf libssl-dev libncurses-dev g++ unzip curl wget git libsrtp2-dev inotify-tools
```

### Bước 2.2: Cài đặt Elixir 1.18 qua asdf

Sử dụng trình quản lý phiên bản cực kỳ phổ biến `asdf` để duy trì đúng phiên bản Erlang/Elixir:
```bash
# Cài đặt asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.bashrc

# Thêm Plugins dành cho Erlang và Elixir
asdf plugin add erlang
asdf plugin add elixir

# Cài đặt chính xác các phiên bản ngôn ngữ
asdf install erlang 27.0
asdf install elixir 1.18.3

# Kiểm tra lại phiên bản sau khi cài
elixir --version
```

### Bước 2.3: Cài đặt FFmpeg & GStreamer

OmniSense sử dụng tập trung sức mạnh vào thư viện GStreamer và phần cứng đa phương tiện để nạp và mã hóa luồng Video NVR.

```bash
# Đối với Ubuntu/Debian (x86_64, máy tính / server thông thường)
sudo apt update
sudo apt install ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavdevice-dev \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-alsa gstreamer1.0-pulseaudio \
    gstreamer1.0-x gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-vaapi \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-rtsp

# Chú ý: Dành riêng cho thiết bị SBC Rockchip như Radxa 5+ (Debian 12+), 
# hãy bổ sung plugin sau để tận dụng NPU/VP hardware
sudo apt-get install librga-dev librga2 gstreamer1.0-rockchip 

# Kiểm tra đảm bảo cài đặt thành công
ffmpeg -version
gst-inspect-1.0
```

### Bước 2.4: Biên dịch Application Dependencies

Dự án kết hợp cả Node để biên dịch mã module C C-Node cho Video processor, và mã Web (Phoenix).

```bash
# 1. Biên dịch Module Xử lý Video (C-node)
cd video_processor
mix deps.get
mix compile

# 2. Định cấu hình Lớp UI Phục Vụ Tính Tương Tác (Phoenix LiveView)
cd ../ui
sudo apt install npm -y
mix deps.get
mix assets.setup

# 3. Khởi tạo cấu trúc dữ liệu SQLite (Database schema)
mix ecto.setup
```

### Bước 2.5: Chạy Máy chủ Phát Triển (Dev Server)

```bash
cd ui
# Cần tắt các tiến trình gst-launch kẹt trước đó (nếu có)
pkill -f "gst-launch"

# Chạy server
mix phx.server
```

Truy cập Dashboard tại thông qua trình duyệt ở địa chỉ: **http://localhost:4000**
*(Tài khoản mặc định: `admin@localhost` / Mật khẩu: `P@ssw0rd`)*

---

## 3. Triển Khai Với Docker & Docker Compose (Khuyến Nghị)

Sử dụng Docker là phương án nhanh nhất và sạch sẽ nhất để vận hành nguyên cụm OmniSense NVR mà không làm ảnh hưởng môi trường máy đích. Hỗ trợ đa kiến trúc CPU (Cross-platform).

### 3.1: Build Standalone Image

Tại thư mục gốc dự án chạy câu lệnh xây dựng Image. (Thực thi được dễ dàng trên nền tảng Server Intel, hoặc chạy trực tiếp trên các thiết bị Edge ARM như Jetson/Rockchip Rpi).
```bash
docker build -t omnisense:latest -f Dockerfile .
```

### 3.2: Chạy Standalone Container Nhanh

Khởi tạo một instance duy nhất.
```bash
docker run --rm -it -p 4000:4000 omnisense:latest
```

Chạy với các **Biến Môi Trường (Environment Variables)** tùy biến cao nhằm thiết đặt bảo mật:
```bash
docker run --rm -it -p 4000:4000 \
  -e CVR_ADMIN_USERNAME=admin@company.com \
  -e CVR_ADMIN_PASSWORD=SuperSecretAdmin123 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 32) \
  -v /var/lib/omnisense_data:/var/lib/cvr \       # Mount Data chứa DB
  -v /mnt/storage_disk:/data/omnisense_nvr \      # Mount luồng MP4 lưu trữ
  omnisense:latest
```

### 3.3: Triển Khai Toàn Diện Với Docker Compose

Docker Compose là tiêu chuẩn để tích hợp kèm nhiều container vi dịch vụ khác (Media Engine, analytic logic).

```bash
cd docker
docker-compose up -d
```
Xem log trạng thái:
```bash
docker-compose logs -f
```

---

## 4. Biên Dịch Môi Trường Sản Xuất (Production Release)

Một "OTP release" độc lập không phụ thuộc source code Elixir trên server để triển khai theo quy trình DevOps/CI-CD cực kỳ mạnh mẽ.

```bash
# 1. Định cấu hình Biến trạng thái OS
export MIX_ENV=prod
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# 2. Chuẩn bị Thư viện phía Server
cd ui
mix deps.get --only prod

# 3. Tổng hợp hóa Assets (Minify & Digest CSS/JS)
mix assets.deploy

# 4. Tạo gói Release (Tập hợp Erlang runtime + App code)
mix release

# 5. Khởi động Release (Lệnh sẽ tạo PID daemon ngầm)
_build/prod/rel/omnisense/bin/omnisense start

# Một số lệnh hữu ích khác:
# _build/prod/rel/omnisense/bin/omnisense stop   (Dừng hệ thống)
# _build/prod/rel/omnisense/bin/omnisense daemon (Vận hành Background)
# _build/prod/rel/omnisense/bin/omnisense remote (Truy cập IEX console trực tiếp)
```

---

## 5. Cấu Hình Khởi Chạy Từ Systemd (Chạy Cùng Hệ Điều Hành)

Cách thông dụng cho triển khai Edge Node hoặc Server truyền thống. Code được duy trì tự động Start khi boot hệ điều hành (Hardware Rebooting).

Tạo tệp service thông qua Root:
```bash
sudo nano /etc/systemd/system/omnisense.service
```

Thêm thông tin Configuration sau (Điều chỉnh `/opt/omnisense/` về đúng đường dẫn Source Code/Release của ban):
```ini
[Unit]
Description=OmniSense AI NVR Video Recorder
After=network.target

[Service]
Type=simple
User=omnisense
Group=omnisense
WorkingDirectory=/opt/omnisense/ui
Environment=MIX_ENV=prod
Environment=SECRET_KEY_BASE=cần_tạo_mỗi_secrect_key_mới
Environment=CVR_HTTP_PORT=4000
Environment=DATABASE_PATH=/var/lib/omnisense/omnisense.db
ExecStart=/opt/omnisense/ui/_build/prod/rel/omnisense/bin/omnisense start
ExecStop=/opt/omnisense/ui/_build/prod/rel/omnisense/bin/omnisense stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Kích hoạt và bật dịch vụ giám sát:
```bash
sudo systemctl daemon-reload
sudo systemctl enable omnisense.service
sudo systemctl start omnisense.service
sudo systemctl status omnisense.service
```

---

## 6. Biến Môi Trường (Environment Variables) Trọng Tâm

Bạn có thể chỉnh cấu hình cho Hệ thống bằng các thiết định môi trường, linh hoạt đối với quy trình Containerize:

| Biến | Chức năng (Ý nghĩa kỹ thuật) | Giá trị mặc định |
|------|------------------------------|------------------|
| `DATABASE_PATH` | Đường dẫn Data layer SQLite quản lý trạng thái, lịch sử camera, Users | `/var/lib/cvr/cvr.db` |
| `CVR_HLS_DIRECTORY` | Phân vùng buffer playlist HLS (Nên mount lên RAM `/tmp` để giảm mòn Ổ đĩa flash ghi xóa) | `/tmp/hls` |
| `CVR_ADMIN_USERNAME` | Email tài khoản quản trị viên NVR gốc (Root User) | `admin@localhost` |
| `CVR_ADMIN_PASSWORD` | Mật khẩu tài khoản ở trên | `P@ssw0rd` |
| `CVR_DOWNLOAD_DIR` | Thư mục dump export / tải video xuống lưu trữ cục bộ | `/tmp/cvr_downloads` |
| `CVR_ICE_SERVERS` | Khởi tạo trung chuyển P2P NAT dành riêng cho truy xuất WebRTC | `[{"urls":"stun:stun.l.google.com:19302"}]` |
| `CVR_JSON_LOGGER` | Kết xuất System Logging định dạng JSON chuẩn (Bật khi có Log Server tập trung) | `true` |
| `SECRET_KEY_BASE` | Chuỗi 64 ký tự chống tấn công Session Tampering bắt buộc cho Security | `<Không>` |

*(Tài liệu này là chuẩn mực về quy trình thiết lập NVR ứng dụng kiến trúc Edge Computing AI.)* 
