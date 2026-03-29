# Repo Map

## Top-level layout
- `ui/` — Phoenix app, business logic, API, LiveView UI, media orchestration entrypoints
- `video_processor/` — Elixir wrappers + native C/NIF codec/processing layer
- `docs/` — architecture notes, especially streaming
- `docker/` — container runtime setup

## Important control-plane files
- `ui/lib/tpro_nvr_web/application.ex` — OTP boot tree
- `ui/lib/tpro_nvr_web/router.ex` — route boundaries
- `ui/lib/tpro_nvr_web/endpoint.ex` — sockets, CORS, parsers, sessions
- `ui/config/runtime.exs` — runtime env behavior and production defaults

## Core contexts
- `ui/lib/tpro_nvr/devices.ex` — device CRUD, startup/shutdown orchestration
- `ui/lib/tpro_nvr/recordings.ex` — recording metadata, snapshots, footage assembly
- `ui/lib/tpro_nvr/cvedix.ex` — AI integration orchestration
- `ui/lib/tpro_nvr/events.ex` — events domain
- `ui/lib/tpro_nvr/accounts.ex` — users/auth tokens

## Main schema files
- `ui/lib/tpro_nvr/model/device.ex`
- `ui/lib/tpro_nvr/model/recording.ex`
- `ui/lib/tpro_nvr/model/run.ex`
- `ui/lib/tpro_nvr/model/schedule.ex`

## Streaming and media hotspots
- `ui/lib/tpro_nvr/gst/pipeline.ex` — hybrid FFmpeg/GStreamer runtime
- `ui/lib/tpro_nvr/gst/supervisor.ex` — pipeline lifecycle
- `ui/lib/tpro_nvr/zlmediakit/stream.ex` — RTSP push / stream handling
- `ui/lib/tpro_nvr/zlmediakit/playback.ex` — playback bridge behavior
- `ui/lib/tpro_nvr/pipelines/gst_hls_playback.ex` — recorded playback generation
- `ui/lib/tpro_nvr_web/controllers/api/device_streaming_controller.ex` — live/playback/snapshot/footage API surface
- `ui/lib/tpro_nvr_web/hls_streaming_monitor.ex` — cleanup/liveness for HLS playback

## AI / CVEDIX hotspots
- `ui/lib/tpro_nvr/cvedix/client.ex`
- `ui/lib/tpro_nvr/cvedix/instance.ex`
- `ui/lib/tpro_nvr/cvedix/event_consumer.ex`
- `ui/lib/tpro_nvr/cvedix/sse_consumer.ex`
- `ui/lib/tpro_nvr/cvedix/sse_auto_starter.ex`

## Native layer
- `video_processor/lib/tpro_nvr/video_processor_nif.ex`
- `video_processor/lib/tpro_nvr/decoder.ex`
- `video_processor/lib/tpro_nvr/encoder.ex`
- `video_processor/c_src/*`

## Migration clusters to inspect
- base devices/recordings/users
- events/LPR
- remote storage
- RTSP mode / proxy changes
- CVEDIX tables and subsequent renames/additions
