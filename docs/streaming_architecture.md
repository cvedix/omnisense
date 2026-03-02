# TProNVR Streaming Architecture

## Overview

TProNVR sử dụng kiến trúc hybrid FFmpeg + GStreamer để xử lý video stream từ các loại camera khác nhau, đảm bảo tương thích tối đa với cả NVR pipeline và AI Video Analytics backend.

---

## Kiến trúc Tổng quan

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           TProNVR System                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────┐                                                       │
│   │   Camera    │ RTSP                                                  │
│   │  (Dahua,    │──────┐                                                │
│   │   Hikvision)│      │                                                │
│   └─────────────┘      │                                                │
│                        ▼                                                │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     FFmpeg Layer                                │   │
│   │  • Nhận RTSP stream từ camera                                   │   │
│   │  • Tương thích tốt với mọi loại camera                          │   │
│   │  • Output: MPEG-TS hoặc RTSP                                    │   │
│   └────────────────────────────────────────────────────────────────┘   │
│                        │                                                │
│         ┌──────────────┼──────────────┐                                │
│         │              │              │                                 │
│         ▼              ▼              ▼                                 │
│   ┌──────────┐  ┌──────────────┐  ┌──────────────┐                     │
│   │ GStreamer│  │  ZLMediaKit  │  │   Direct     │                     │
│   │  (NVR)   │  │   (Proxy)    │  │   Storage    │                     │
│   └──────────┘  └──────────────┘  └──────────────┘                     │
│         │              │                                                │
│         ▼              ▼                                                │
│   ┌──────────┐  ┌──────────────┐                                       │
│   │HLS + MP4 │  │ CVEDIX AI    │                                       │
│   │Recording │  │ Analytics    │                                       │
│   └──────────┘  └──────────────┘                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Module: Hybrid FFmpeg-GStreamer Pipeline

### Mục đích
Xử lý video từ camera cho NVR (HLS streaming + MP4 recording).

### Luồng xử lý

```
Camera (RTSP)
     │
     ▼
┌─────────────────────────────────────────┐
│              FFmpeg                      │
│  ffmpeg -rtsp_transport tcp             │
│         -i "rtsp://camera..."           │
│         -c:v copy -an                   │
│         -f mpegts pipe:1                │
└─────────────────────────────────────────┘
     │
     │ MPEG-TS via pipe (stdout → stdin)
     ▼
┌─────────────────────────────────────────┐
│            GStreamer                     │
│  fdsrc fd=0                             │
│    ! tsdemux                            │
│    ! h264parse                          │
│    ! mppvideodec     ← Rockchip HW      │
│    ! tee                                │
│      ├─► mpph264enc → HLS               │
│      └─► mpph265enc → MP4 Recording     │
└─────────────────────────────────────────┘
```

### Files liên quan
- `lib/tpro_nvr/gst/pipeline.ex` - Pipeline GenServer
- `lib/tpro_nvr/gst/supervisor.ex` - Supervisor

### Hàm chính
| Hàm | Mô tả |
|-----|-------|
| `start_hybrid_pipeline/1` | Khởi động FFmpeg + GStreamer |
| `stop_hybrid_pipeline/1` | Dừng cả 2 process |
| `build_ffmpeg_cmd/1` | Tạo lệnh FFmpeg |
| `build_gstreamer_cmd/1` | Tạo lệnh GStreamer |

---

## Module: ZLMediaKit Stream Push

### Mục đích
Push stream lên ZLMediaKit proxy để AI Analytics backend có thể nhận.

### Luồng xử lý

```
┌────────────────────────────────────────────────────────────────────┐
│                    Khi Enable AI Analytics                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Camera (RTSP)                                                     │
│        │                                                            │
│        ▼                                                            │
│   ┌─────────────────────────────────────┐                          │
│   │         FFmpeg Push                  │                          │
│   │  ffmpeg -i "rtsp://camera..."       │                          │
│   │         -c:v copy                    │                          │
│   │         -f rtsp                      │                          │
│   │         "rtsp://localhost:8554/..."  │                          │
│   └─────────────────────────────────────┘                          │
│                    │                                                │
│                    ▼                                                │
│   ┌─────────────────────────────────────┐                          │
│   │         ZLMediaKit                   │ Docker Container         │
│   │  rtsp://localhost:8554/live/{id}     │                          │
│   └─────────────────────────────────────┘                          │
│                    │                                                │
│                    ▼                                                │
│   ┌─────────────────────────────────────┐                          │
│   │     CVEDIX AI Analytics             │                          │
│   │  • Intrusion Detection              │                          │
│   │  • People Counting                  │                          │
│   │  • License Plate Recognition        │                          │
│   └─────────────────────────────────────┘                          │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### Files liên quan
- `lib/tpro_nvr/zlmediakit/stream.ex` - GenServer quản lý FFmpeg push
- `lib/tpro_nvr/zlmediakit/supervisor.ex` - Supervisor
- `lib/tpro_nvr/cvedix.ex` - Tích hợp với AI Analytics
- `lib/tpro_nvr/cvedix/instance.ex` - CVEDIX instance management

### API

```elixir
# Start push stream cho device
TProNVR.ZLMediaKit.Stream.start_push(device_id, rtsp_url)

# Stop push stream
TProNVR.ZLMediaKit.Stream.stop_push(device_id)

# Lấy URL stream trên ZLMediaKit
TProNVR.ZLMediaKit.Stream.get_stream_url(device_id)
# → {:ok, "rtsp://localhost:8554/live/{device_id}"}

# Kiểm tra stream đang push?
TProNVR.ZLMediaKit.Stream.pushing?(device_id)
# → true/false
```

---

## Cấu hình

### config/config.exs

```elixir
config :tpro_nvr,
  # ZLMediaKit configuration
  zlmediakit: [
    host: "localhost",
    rtsp_port: 8554,
    enabled: true
  ],
  
  # CVEDIX AI Analytics
  cvedix: [
    base_url: "http://localhost:3546",
    enabled: true
  ]
```

---

## Tự động hóa

### Khi enable AI Analytics (CVEDIX)

```
User clicks "Enable AI Analytics"
           │
           ▼
┌──────────────────────────────────┐
│  CVEDIX.setup_intrusion_detection │
│                                   │
│  1. Start ZLMediaKit push         │◄── Auto
│  2. Create CVEDIX instance        │
│  3. Set input = ZLMediaKit URL    │◄── Auto
│  4. Start AI processing           │
└──────────────────────────────────┘
```

### Khi disable AI Analytics

```
User clicks "Disable AI Analytics"
           │
           ▼
┌──────────────────────────────────┐
│ CVEDIX.stop_intrusion_detection  │
│                                   │
│  1. Stop ZLMediaKit push          │◄── Auto
│  2. Stop CVEDIX instance          │
│  3. Delete instance               │
└──────────────────────────────────┘
```

---

## Troubleshooting

### Kiểm tra FFmpeg push đang chạy

```bash
ps aux | grep "ffmpeg.*rtsp.*8554"
```

### Kiểm tra stream trên ZLMediaKit

```bash
ffprobe rtsp://localhost:8554/live/{device_id}
```

### Kiểm tra log

```bash
grep "ZLMediaKit" /var/log/nvr.log
grep "CVEDIX" /var/log/nvr.log
```
