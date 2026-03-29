---
name: omnisense-source-audit
description: Analyze, audit, and navigate the Omnisense/TProNVR codebase. Use when working on this repository for: (1) understanding module boundaries, data flow, and runtime architecture, (2) tracing camera ingest, recording, HLS/WebRTC/live streaming, ZLMediaKit, GStreamer, FFmpeg, or CVEDIX integration, (3) reviewing technical debt, security risks, or production failure modes, (4) planning refactors or changes safely in media pipeline and Phoenix contexts, or (5) onboarding another agent to this repo quickly.
---

# Omnisense Source Audit

Treat this repository as a video-surveillance/NVR system with a Phoenix control plane and multiple media runtimes. Optimize for correctness and system understanding before proposing changes.

## Read this skill when
The task is about understanding, auditing, debugging, refactoring, or extending this repo.

## Mental model
Map the repo into these layers first:

1. **Web/control plane**
   - `ui/lib/tpro_nvr_web/*`
   - Phoenix endpoint, router, controllers, LiveViews, channels, auth, telemetry.

2. **Core business contexts**
   - `ui/lib/tpro_nvr/accounts.ex`
   - `ui/lib/tpro_nvr/devices.ex`
   - `ui/lib/tpro_nvr/recordings.ex`
   - `ui/lib/tpro_nvr/events.ex`
   - `ui/lib/tpro_nvr/remote_storages.ex`
   - `ui/lib/tpro_nvr/cvedix.ex`

3. **Domain models / schemas**
   - `ui/lib/tpro_nvr/model/*`
   - Check embeds on `Device` first: stream config, credentials, storage config, snapshot config, settings.

4. **Media runtime / external-process orchestration**
   - `ui/lib/tpro_nvr/gst/*`
   - `ui/lib/tpro_nvr/zlmediakit/*`
   - `ui/lib/tpro_nvr/pipelines/*`
   - `ui/lib/tpro_nvr/live_stream/*`
   - `ui/lib/tpro_nvr/hls/*`

5. **Native / codec layer**
   - `video_processor/lib/*`
   - `video_processor/c_src/*`

6. **Persistence and schema evolution**
   - `ui/priv/repo/migrations/*`

## Default audit workflow
Use this order unless the task is narrowly scoped:

1. Read `README.md` and `docs/streaming_architecture.md`.
2. Read runtime boot path:
   - `ui/lib/tpro_nvr_web/application.ex`
   - `ui/config/runtime.exs`
   - `ui/lib/tpro_nvr_web/router.ex`
   - `ui/lib/tpro_nvr_web/endpoint.ex`
3. Identify the relevant context module.
4. Trace one level down into:
   - schema/model
   - controller/liveview/channel entrypoint
   - background worker/supervisor/process manager
5. Check migrations for the feature area.
6. Check tests touching the same subsystem.
7. Only then propose changes or conclusions.

## Fast navigation heuristics

### Device lifecycle
Start with:
- `ui/lib/tpro_nvr/devices.ex`
- `ui/lib/tpro_nvr/model/device.ex`
- `ui/lib/tpro_nvr/devices/supervisor.ex`

Questions to answer:
- how device is created/updated/deleted
- which directories are created
- what starts/stops on state change
- whether both Membrane and GStreamer paths are active

### Live streaming / HLS / snapshot / footage
Start with:
- `ui/lib/tpro_nvr_web/controllers/api/device_streaming_controller.ex`
- `ui/lib/tpro_nvr/gst/pipeline.ex`
- `ui/lib/tpro_nvr/zlmediakit/stream.ex`
- `ui/lib/tpro_nvr/pipelines/gst_hls_playback.ex`
- `ui/lib/tpro_nvr_web/hls_streaming_monitor.ex`

Distinguish clearly between:
- live HLS redirect/proxy behavior
- recorded playback HLS generation
- snapshot from live source vs recorded source
- footage export/assembly

### Recording flow
Start with:
- `ui/lib/tpro_nvr/recordings.ex`
- `ui/lib/tpro_nvr/recordings/importer.ex`
- `ui/lib/tpro_nvr/recordings/sync_worker.ex`
- `ui/lib/tpro_nvr/recordings/video_assembler.ex`
- `ui/lib/tpro_nvr/model/recording.ex`
- `ui/lib/tpro_nvr/model/run.ex`

Check:
- filename convention
- path convention
- how DB metadata stays in sync with disk
- how clock jumps / run correction are handled

### AI / CVEDIX flow
Start with:
- `ui/lib/tpro_nvr/cvedix.ex`
- `ui/lib/tpro_nvr/cvedix/client.ex`
- `ui/lib/tpro_nvr/cvedix/instance.ex`
- `ui/lib/tpro_nvr/cvedix/event_consumer.ex`
- `ui/lib/tpro_nvr/cvedix/sse_consumer.ex`
- latest CVEDIX migrations

Check:
- local DB instance state vs remote engine state
- who subscribes/unsubscribes
- whether startup/shutdown is idempotent
- what happens on remote failure

### Auth / API security
Start with:
- `ui/lib/tpro_nvr_web/user_auth.ex`
- `ui/lib/tpro_nvr_web/router.ex`
- `ui/lib/tpro_nvr_web/endpoint.ex`
- `ui/config/runtime.exs`

Always inspect:
- default credentials/secrets
- token transport in query params vs headers
- CORS, check_origin, cookie/session behavior
- admin route boundaries

### Native / NIF layer
Start with:
- `video_processor/lib/tpro_nvr/video_processor_nif.ex`
- `video_processor/lib/tpro_nvr/*.ex`
- `video_processor/c_src/*`

Assume NIF changes are high risk. Highlight:
- ABI/build assumptions
- memory ownership
- crash surface into BEAM
- lack of dirty scheduler usage if relevant

## Repo-specific cautions

1. **Naming is inconsistent**
   Expect `omnisense`, `CVR`, `TProNVR`, and `CVEDIX` to refer to overlapping parts of the system.

2. **External process orchestration is a risk hotspot**
   Be cautious around code using:
   - `bash -c`
   - `Port.open`
   - `pkill -f`
   - FFmpeg/GStreamer/ZLMediaKit shell commands

3. **Do not assume WebRTC is complete**
   Verify implementation details. Some paths may be placeholders/stubs.

4. **Device model contains business rules and infrastructure rules**
   `model/device.ex` mixes schema, path conventions, vendor heuristics, stream URL logic, and proxy behavior.

5. **Recorded playback and live streaming are different subsystems**
   Do not merge them conceptually in analysis.

## Output style for audits
When reporting findings, group them into:
- architecture understanding
- strengths
- risks/bugs
- production failure modes
- refactor opportunities
- recommended next actions

Prefer repo-specific observations over generic best practices.

## Reference files
Read these as needed:
- `references/repo-map.md` for subsystem map
- `references/hotspots.md` for high-risk files and recurring failure patterns
