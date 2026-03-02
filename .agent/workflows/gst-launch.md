---
description: GStreamer pipeline commands for TProNVR
---

# GStreamer Launch Commands

## Full Pipeline with ZLMediaKit (rtspclientsink)

### Hybrid Pipeline with RTSP push to ZLMediaKit

```bash
# turbo
ffmpeg -hide_banner -loglevel error \
  -rtsp_transport tcp \
  -i "rtsp://admin:password@192.168.1.200:554/stream" \
  -c:v copy -an \
  -f mpegts pipe:1 | \
gst-launch-1.0 -e \
  fdsrc fd=0 ! tsdemux ! h264parse ! mppvideodec name=dec \
  dec. ! tee name=raw_tee \
  raw_tee. ! queue max-size-buffers=100 ! mpph264enc bps=2000000 gop=30 \
  ! h264parse ! tee name=hls_tee \
  hls_tee. ! queue max-size-buffers=50 leaky=downstream ! hlssink2 \
    location="/tmp/test/segment%05d.ts" \
    playlist-location="/tmp/test/index.m3u8" \
    target-duration=2 max-files=10 \
  hls_tee. ! queue max-size-buffers=50 leaky=downstream \
  ! rtspclientsink location="rtsp://localhost:8554/live/test" protocols=tcp
```

---

## Push to ZLMediaKit (rtspclientsink)

### GStreamer RTSP push (NEW - saves RAM!)

```bash
# turbo
gst-launch-1.0 -e \
  rtspsrc location="rtsp://admin:password@192.168.1.200:554/stream" latency=200 protocols=tcp \
  ! rtph264depay ! h264parse ! tee name=t \
  t. ! queue ! rtspclientsink location="rtsp://localhost:8554/live/test" protocols=tcp
```

### Verify ZLMediaKit stream

```bash
# turbo
ffprobe rtsp://localhost:8554/live/test_stream
```

---

## HLS Output

```bash
# turbo
gst-launch-1.0 -e \
  rtspsrc location="rtsp://admin:password@192.168.1.100:554/stream" latency=200 protocols=tcp \
  ! rtph264depay ! h264parse ! mppvideodec \
  ! mpph264enc bps=2000000 gop=30 \
  ! h264parse ! hlssink2 \
    location="/tmp/hls/segment%05d.ts" \
    playlist-location="/tmp/hls/index.m3u8" \
    target-duration=2 max-files=10
```

## MP4 Recording (H.265)

```bash
# turbo
gst-launch-1.0 -e \
  rtspsrc location="rtsp://admin:password@192.168.1.100:554/stream" latency=200 protocols=tcp \
  ! rtph264depay ! h264parse ! mppvideodec \
  ! mpph265enc bps=1500000 gop=60 \
  ! h265parse ! splitmuxsink \
    location="/tmp/recording_%05d.mp4" \
    max-size-time=60000000000
```

---

## Debug Commands

```bash
# turbo
gst-launch-1.0 videotestsrc ! autovideosink
```

```bash
# turbo
gst-inspect-1.0 | grep -E "mpp|rtsp"
```

---

## Element Reference

| Element | Description |
|---------|-------------|
| `mppvideodec` | Rockchip HW H.264/H.265 decoder |
| `mpph264enc` | Rockchip HW H.264 encoder |
| `mpph265enc` | Rockchip HW H.265 encoder |
| `rtspclientsink` | Push stream via RTSP (to ZLMediaKit) |
| `hlssink2` | HLS output |
| `splitmuxsink` | MP4 recording with segmentation |

## Common Options

| Option | Description |
|--------|-------------|
| `-e` | Send EOS on SIGINT (clean shutdown) |
| `latency=200` | RTSP buffer latency in ms |
| `protocols=tcp` | Use TCP for RTSP |
| `leaky=downstream` | Drop frames if queue full |
| `bps=2000000` | Bitrate in bits/sec |
| `gop=30` | Group of Pictures size |
