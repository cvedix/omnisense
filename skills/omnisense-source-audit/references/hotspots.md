# Hotspots

## High-risk files

### 1. `ui/lib/tpro_nvr/gst/pipeline.ex`
Why it matters:
- orchestrates FFmpeg + GStreamer
- handles codec probing, recording, HLS-related behavior, snapshot behavior, sub-stream push, fallback mode

Common risks:
- shell command construction
- process restart loops
- mode switching bugs
- resource leaks
- hidden coupling to ZLMediaKit and controller expectations

### 2. `ui/lib/tpro_nvr_web/controllers/api/device_streaming_controller.ex`
Why it matters:
- one API surface for live HLS, playback HLS, segments, snapshot, footage, bif

Common risks:
- mixed responsibilities
- edge-case file cleanup
- auth/token exposure on streaming endpoints
- confusion between live and playback code paths

### 3. `ui/lib/tpro_nvr/model/device.ex`
Why it matters:
- schema plus path conventions plus vendor heuristics plus RTSP URL resolution

Common risks:
- business rules mixed with infrastructure concerns
- vendor-specific behavior buried in schema layer
- fragile proxy/stream-key logic

### 4. `ui/config/runtime.exs` and `ui/lib/tpro_nvr_web/endpoint.ex`
Why they matter:
- secrets, credentials, sockets, CORS, prod behavior

Common risks:
- insecure defaults
- permissive origin policy
- environment parsing bugs

### 5. `ui/lib/tpro_nvr/cvedix.ex` + client/consumers
Why they matter:
- local/remote state sync
- startup/stop orchestration
- analytics event ingestion

Common risks:
- idempotency gaps
- orphan consumers/subscriptions
- partial failure between DB and remote runtime

## Audit questions by theme

### Security
- Are there hardcoded secrets or unsafe prod fallbacks?
- Are streaming tokens exposed in query strings?
- Are sockets/CORS too permissive?
- Is shell command input sanitized?

### Reliability
- What happens if external process exits unexpectedly?
- What state is persisted vs inferred?
- Can DB and disk diverge?
- Can local and remote CVEDIX states diverge?

### Maintainability
- Is a controller/context/model doing too much?
- Are responsibilities clear?
- Are naming inconsistencies hiding conceptual duplication?

### Production behavior
- What happens under disk pressure?
- What happens when camera source is flaky?
- What happens when CVEDIX is unavailable?
- What cleanup path handles temp files and dead playback sessions?
