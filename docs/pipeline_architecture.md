# OmniSense Pipeline Architecture
## Tài liệu kỹ thuật cho người phát triển

> **Phiên bản:** 1.0
> **Ngày:** 2026-04-04
> **Kiến trúc:** GStreamer/CVEDIX SDK, C++

---

## Mục lục

1. [Tổng quan hệ thống](#1-tổng-quan-hệ-thống)
2. [Luồng pipeline chuẩn](#2-luồng-pipeline-chuẩn)
3. [Chi tiết từng thành phần](#3-chi-tiết-từng-thành-phần)
   - [3.1 RTSP Source Node](#31-rtsp-source-node)
   - [3.2 YOLO Detector Node](#32-yolo-detector-node)
   - [3.3 ByteTrack Tracker Node](#33-bytetrack-tracker-node)
   - [3.4 BA (Behavior Analysis) Nodes](#34-ba-behavior-analysis-nodes)
   - [3.5 Broker Nodes](#35-broker-nodes)
4. [Chạy nhiều Inference Node trong một Pipeline](#4-chạy-nhiều-inference-node-trong-một-pipeline)
5. [Chạy nhiều BA Node trong một Pipeline](#5-chạy-nhiều-ba-node-trong-một-pipeline)
6. [Hệ thống Solution Config & Parameter](#6-hệ-thống-solution-config--parameter)
7. [Luồng lắp ráp Pipeline (Build Pipeline)](#7-luồng-lắp-ráp-pipeline-build-pipeline)
8. [Chiến lược kết nối Node (attach_to)](#8-chiến-lược-kết-nối-node-attach_to)
9. [Hướng dẫn thực hành](#9-hướng-dẫn-thực-hành)

---

## 1. Tổng quan hệ thống

OmniSense sử dụng kiến trúc **node graph** xây trên **CVEDIX SDK** (GStreamer backend). Mỗi processing stage là một `cvedix_node` nhận frame qua `attach_to()`. Pipeline được lắp ráp runtime từ declarative **Solution configs** và **CreateInstanceRequest**.

```
┌─────────────────────────────────────────────────────────┐
│                   CreateInstanceRequest                 │
│  { solutionId, additionalParams, instanceId, ... }       │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│              SolutionRegistry::getSolution()            │
│         → SolutionConfig { pipeline[], defaults{} }     │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│          PipelineBuilder::buildPipeline()               │
│   Xử lý multi-source, tạo nodes, kết nối graph        │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│      vector<shared_ptr<cvedix_node>> — Node Graph       │
│                  Sẵn sàng pipeline->run()               │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Luồng pipeline chuẩn

```
┌────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────┐    ┌──────────────────────────┐
│  rtsp_src  │───▶│ yolo_detector │───▶│  bytetrack   │───▶│  BA Node   │───▶│       Broker Node       │
│ (GStreamer)│    │   (YOLOv8)    │    │  (Tracker)    │    │ (Analysis) │    │  (Socket/MQTT/Console)  │
└────────────┘    └──────────────┘    └──────────────┘    └─────┬──────┘    └──────────────────────────┘
                                                                   │
                                                            ┌──────▼──────┐
                                                            │  BA Node    │
                                                            │  _osd       │───▶ screen_des / rtmp_des
                                                            └─────────────┘
```

### Ví dụ: Pipeline hoàn chỉnh
```
rtsp_src → yolo_detector → bytetrack → ba_crossline
                                          │
                        ┌─────────────────┼─────────────────┐
                        │                 │                 │
                        ▼                 ▼                 ▼
              ba_socket_broker    json_console_broker   ba_crossline_osd
                                                              │
                                                             ▼
                                                       screen_des
                                                              │
                                                             ▼
                                                         rtmp_des
```

---

## 3. Chi tiết từng thành phần

### 3.1 RTSP Source Node

**File:** `src/core/pipeline_builder_source_nodes.cpp`

**Hàm:** `PipelineBuilderSourceNodes::createRTSPSourceNode()`

#### Constructor
```cpp
cvedix_rtsp_src_node(name, channel, rtsp_url, resize_ratio,
                     gst_decoder_name, skip_interval, codec_type)
```

#### Tham số và ưu tiên

| Tham số | Mức 1 (cao nhất) | Mức 2 | Mức 3 | Mặc định |
|---|---|---|---|---|
| `rtsp_url` | param `rtsp_url` | `RTSP_SRC_URL` | `RTSP_URL` | **Bắt buộc** |
| `resize_ratio` | `RESIZE_RATIO` | param `resize_ratio` | param `scale` | `0.6f` |
| `gst_decoder_name` | `GST_DECODER_NAME` | param `gst_decoder_name` | auto-detect | `avdec_h264` |
| `skip_interval` | `SKIP_INTERVAL` | param `skip_interval` | — | `0` |
| `codec_type` | `CODEC_TYPE` | param `codec_type` | — | `"h264"` |
| `rtsp_transport` | `RTSP_TRANSPORT` | `GST_RTSP_PROTOCOLS` env | env `RTSP_TRANSPORT` | auto |

#### Decoder GPU-first (validate qua `gst-inspect-1.0`)
```
nvh264dec     → NVIDIA GPU (NVDEC)       ✅ checked first
vaapih264dec  → Intel GPU (VAAPI)        ✅ checked second
qsvh264dec    → Intel QuickSync          ✅ checked third
avdec_h264    → Software (FFmpeg)        ✅ always fallback
```

#### Hỗ trợ multi-stream
```cpp
// additionalParams["FILE_PATHS"] — JSON array
[{
  "file_path": "/path/to/video1.mp4",
  "channel": 0,
  "resize_ratio": 0.4,
  "gst_decoder_name": "avdec_h264",
  "skip_interval": 0,
  "codec_type": "h264"
}, {
  "file_path": "rtsp://camera2/stream",
  "channel": 1,
  "resize_ratio": 0.6
}]

// Hoặc dùng RTSP_URLS
additionalParams["RTSP_URLS"] = R"([
  {"rtsp_url": "rtsp://cam1/stream", "channel": 0},
  {"rtsp_url": "rtsp://cam2/stream", "channel": 1}
])";
```

---

### 3.2 YOLO Detector Node

**File:** `src/core/pipeline_builder_detector_nodes.cpp`

**Hàm:** `PipelineBuilderDetectorNodes::createYOLODetectorNode()`

#### Constructor (Legacy OpenCV DNN)
```cpp
cvedix_yolo_detector_node(name, modelPath, modelConfigPath, labelsPath,
                          inputWidth, inputHeight, batchSize, classIdOffset,
                          scoreThreshold, confidenceThreshold, nmsThreshold)
```

#### Constructor (Plugin API — khi `CVEDIX_YOLO_DETECTOR_PLUGIN_API` defined)
```cpp
cvedix_yolo_detector_node(name, modelPath, labelsPath,
                          confThresh, nmsThreshold, classIdOffset, backend)
```

Backend: `AUTO | TENSORRT | OPENVINO | ONNX`

#### Tham số model path (3 mức ưu tiên)
```
Mức 1: param weights_path / model_path
Mức 2: additionalParams["WEIGHTS_PATH"] / additionalParams["MODEL_PATH"]
Mức 3: fallback → yolov8n-face.onnx (qua resolveModelPath)
```

#### GPU ordering
- `ensureGPUFirstInDeviceList()` — đưa GPU lên đầu danh sách thiết bị
- `ensureCPUFirstInDeviceList()` — triggered khi `FORCE_CPU_INFERENCE=1`
- cuDNN/CUDA errors → gợi ý `OPENCV_DNN_BACKEND=OPENCV`

#### Output
```json
{
  "detections": [
    { "bbox": [x, y, w, h], "score": 0.92, "class_id": 2 },
    { "bbox": [x, y, w, h], "score": 0.87, "class_id": 0 }
  ]
}
```

---

### 3.3 ByteTrack Tracker Node

**File:** `src/core/pipeline_builder_other_nodes.cpp` (dòng 53–146)

**Hàm:** `PipelineBuilderOtherNodes::createByteTrackNode()`

#### Constructor
```cpp
cvedix_bytetrack_node(name, track_for, track_thresh, high_thresh,
                      match_thresh, track_buffer, frame_rate)
```

#### Tham số mặc định

| Tham số | Giá trị | Ý nghĩa |
|---|---|---|
| `track_thresh` | `0.5` | Ngưỡng detection confidence để **tạo** track mới |
| `high_thresh` | `0.6` | Ngưỡng cao cho tracking |
| `match_thresh` | `0.8` | IOU threshold ghép detection ↔ track |
| `track_buffer` | `30` | Frame giữ track sống khi mất detection |
| `frame_rate` | `30` | FPS video (tính thời gian buffer) |
| `track_for` | `NORMAL` | `NORMAL` hoặc `FACE` |

#### Routing trong `createNode()` (pipeline_builder.cpp ~2194)

| Node type string | Hành động |
|---|---|
| `bytetrack` / `bytetrack_track` | `createByteTrackNode()` ← **DEFAULT** |
| `sort_track` | `createSORTTrackNode()` (IOU tracker đơn giản) |
| `ocsort` / `ocsort_track` | **THROWS** — tạm disabled (cereal/rapidxml conflict) |

#### Output
```json
{
  "tracks": [
    { "track_id": 12, "bbox": [x, y, w, h], "score": 0.92, "class_id": 2 },
    { "track_id": 15, "bbox": [x, y, w, h], "score": 0.87, "class_id": 0 }
  ]
}
```

---

### 3.4 BA (Behavior Analysis) Nodes

**File:** `src/core/pipeline_builder_behavior_analysis_nodes.cpp`

#### Tất cả loại BA Node

| Node Type | SDK Class | Mục đích |
|---|---|---|
| `ba_crossline` | `cvedix_ba_line_crossline_node` | Phát hiện cắt đường |
| `ba_jam` | `cvedix_ba_area_jam_node` | Phát hiện kẹt xe trong vùng |
| `ba_stop` | `cvedix_ba_stop_node` | Phát hiện dừng đỗ trong vùng |
| `ba_loitering` | `cvedix_ba_area_loitering_node` | Phát hiện lảng vảng |
| `ba_area_enter_exit` | `cvedix_ba_area_enter_exit_node` | Phát hiện ra/vào vùng |
| `ba_line_counting` | `cvedix_ba_line_counting_node` | Đếm người/xe qua line |
| `ba_crowding` | `cvedix_ba_area_crowding_node` | Phát hiện đám đông |

#### Cấu hình Crossline (ưu tiên cao → thấp)
```json
// Mức 1: CrossingLines JSON (additionalParams)
additionalParams["CrossingLines"] = R"([
  {
    "name": "Lane 1",
    "color": [255, 0, 0, 255],
    "direction": "BOTH",
    "coordinates": {"start": {"x": 100, "y": 400}, "end": {"x": 600, "y": 400}}
  },
  {
    "name": "Lane 2",
    "color": [0, 255, 0, 255],
    "direction": "IN",
    "coordinates": {"start": {"x": 100, "y": 500}, "end": {"x": 600, "y": 500}}
  }
])"

// Mức 2: Legacy params
additionalParams["CROSSLINE_START_X"] = "100"
additionalParams["CROSSLINE_START_Y"] = "400"
additionalParams["CROSSLINE_END_X"] = "600"
additionalParams["CROSSLINE_END_Y"] = "400"

// Mức 3: Solution config parameters
```

#### Cấu hình Jam Zone
```json
additionalParams["JamZones"] = R"([
  {
    "id": "zone1",
    "name": "Intersection A",
    "roi": [
      {"x": 100, "y": 100}, {"x": 500, "y": 100},
      {"x": 500, "y": 300}, {"x": 100, "y": 300}
    ],
    "enabled": true,
    "check_interval_frames": 20,
    "check_min_hit_frames": 50,
    "check_max_distance": 8,
    "check_min_stops": 8,
    "check_notify_interval": 10
  }
])"
```

#### Cấu hình Stop Zone
```json
additionalParams["StopZones"] = R"([
  {
    "id": "stop1",
    "name": "Loading Zone",
    "roi": [
      {"x": 0, "y": 0}, {"x": 10, "y": 0},
      {"x": 10, "y": 10}, {"x": 0, "y": 10}
    ]
  }
])"
```

#### Direction enum cho Crossline
```cpp
enum cvedix_ba_direct_type {
    IN   = 0,   // Hướng đi vào (Up/Down tùy orientation)
    OUT  = 1,   // Hướng đi ra
    BOTH = 2    // Cả hai hướng (default)
};
```

#### BA OSD Node (compulsory cho visualization)
Mỗi BA node cần một OSD node đi kèm để vẽ overlay:

| BA Node | OSD Node | SDK Class |
|---|---|---|
| `ba_crossline` | `ba_crossline_osd` | `cvedix_ba_line_crossline_osd_node` |
| `ba_jam` | `ba_jam_osd` | `cvedix_ba_area_jam_osd_node` |
| `ba_stop` | `ba_stop_osd` | `cvedix_ba_stop_osd_node` |
| `ba_loitering` | `ba_loitering_osd` | companion OSD |
| `ba_area_enter_exit` | `ba_area_enter_exit_osd` | `cvedix_ba_area_enter_exit_osd_node` |
| `ba_crowding` | `ba_crowding_osd` | companion OSD |

---

### 3.5 Broker Nodes

**File:** `src/core/pipeline_builder_broker_nodes.cpp`

#### Tất cả loại Broker

| Node Type | Transport | Mặc định cho |
|---|---|---|
| `json_console_broker` | stdout | NORMAL/FACE/TEXT/POSE |
| `json_enhanced_console_broker` | stdout + full-frame | NORMAL |
| `ba_socket_broker` | TCP socket | BA events |
| `sse_broker` | HTTP SSE | NORMAL |
| `json_kafka_broker` | Kafka | NORMAL (`CVEDIX_WITH_KAFKA`) |
| `embeddings_socket_broker` | TCP socket | Face embedding |
| `plate_socket_broker` | TCP socket | License plate |
| `expr_socket_broker` | TCP socket | Expression |

#### Cấu hình MQTT (hiện tại disabled)
```cpp
MQTT_BROKER_URL   → "mqtt://broker.example.com"  (default: "localhost")
MQTT_PORT         → 1883                          (default)
MQTT_TOPIC        → "events"                      (default)
MQTT_USERNAME     → auth username
MQTT_PASSWORD     → auth password
```
> ⚠️ MQTT brokers hiện tại crash — cần fix trước khi enable.

#### Cấu hình Socket Broker
```cpp
BA_SOCKET_IP      → "127.0.0.1"  (default)
BA_SOCKET_PORT    → 8080          (default)
```

#### Cấu hình SSE Broker
```cpp
port     = 8090           (default)
endpoint = "/events"      (default)
```

#### Auto-injection
Nếu `MQTT_BROKER_URL` set + có BA node nhưng chưa có broker:
```cpp
// autoInjectOptionalNodes() — pipeline_builder.cpp ~1600
// Tự động inject MQTT broker, gắn song song với BA node
```

---

## 4. Chạy nhiều Inference Node trong một Pipeline

### 4.1 Cơ chế hoạt động

**Có thể chạy nhiều detector node** — không có deduplication trong builder.

Mỗi entry trong `solution.pipeline` tạo một node riêng biệt:
```cpp
// pipeline_builder.cpp dòng 528+
for (const auto &nodeConfig : solution.pipeline) {
    auto node = createNode(modifiedNodeConfig, ...);
    if (node) {
        nodes.push_back(node);
        nodeTypes.push_back(nodeConfig.nodeType);  // ← KHÔNG deduplicate
    }
}
```

### 4.2 Nhiều Detector cùng loại (Multi-head detection)

```json
{
  "solutionId": "multi_detector",
  "pipeline": [
    {
      "nodeType": "rtsp_src",
      "nodeName": "rtsp_src_{instanceId}",
      "parameters": { "rtsp_url": "${RTSP_URL}" }
    },
    {
      "nodeType": "yolo_detector",
      "nodeName": "person_detector_{instanceId}",
      "parameters": {
        "weights_path": "/models/yolov8n-person.onnx",
        "class_filter": "person,car"
      }
    },
    {
      "nodeType": "yolo_detector",
      "nodeName": "vehicle_detector_{instanceId}",
      "parameters": {
        "weights_path": "/models/yolov8n-vehicle.onnx",
        "class_filter": "truck,bus,bicycle"
      }
    },
    {
      "nodeType": "yolo_detector",
      "nodeName": "face_detector_{instanceId}",
      "parameters": {
        "weights_path": "/models/yunet.onnx"
      }
    },
    {
      "nodeType": "bytetrack",
      "nodeName": "tracker_{instanceId}",
      "parameters": { "track_thresh": "0.5" }
    },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline_{instanceId}",
      "parameters": { "CrossingLines": "${CrossingLines}" }
    }
  ]
}
```

### 4.3 Nhiều Detector gắn vào multi-source

Khi dùng `FILE_PATHS`/`RTSP_URLS`, detector/tracker tự động fan-out:

```cpp
// pipeline_builder.cpp dòng 614–626
if (hasMultipleSources && !multipleSourceNodes.empty()) {
    if (nodeConfig.nodeType == "yolo_detector" ||
        nodeConfig.nodeType == "sort_track" ||
        nodeConfig.nodeType == "sort_tracker") {
        node->attach_to(multipleSourceNodes);  // ← 1 call, gắn TẤT CẢ sources
        continue;  // Skip normal connection logic
    }
}
```

```
   rtsp_src_0 ──┐
                ├──▶ person_detector ──▶ bytetrack ──▶ ba_crossline
   rtsp_src_1 ──┘

Khi multi-source:
   rtsp_src_0 ──┐
   rtsp_src_1 ──┼──▶ person_detector ──▶ bytetrack ──▶ ba_crossline
   rtsp_src_2 ──┘
```

### 4.4 Cascade Detection (Detector → Detector)

Detector có thể nối tiếp — detector sau nhận output từ detector trước:

```json
{
  "pipeline": [
    { "nodeType": "rtsp_src", "nodeName": "src", "parameters": {} },
    {
      "nodeType": "yolo_detector",
      "nodeName": "stage1_detector",
      "parameters": { "weights_path": "/models/yolov8n-face.onnx" }
    },
    {
      "nodeType": "yolo_detector",
      "nodeName": "stage2_detector",
      "parameters": {
        "weights_path": "/models/attributes.onnx",
        "input_from": "stage1_detector"
      }
    },
    { "nodeType": "bytetrack", "nodeName": "tracker", "parameters": {} },
    { "nodeType": "ba_crossline", "nodeName": "crossline", "parameters": {} }
  ]
}
```

### 4.5 Tài nguyên GPU cho multi-inference

Mỗi detector có device list riêng. Cấu hình qua `additionalParams`:

```cpp
// Model resolution và device assignment
additionalParams["AUTO_DEVICE_LIST"] = "0,1";     // GPU 0,1
additionalParams["FORCE_CPU_INFERENCE"] = "0";    // 1 = force CPU
additionalParams["OPENCV_DNN_BACKEND"] = "OPENCV"; // fallback nếu GPU lỗi

// Hoặc per-detector
{
  "nodeType": "yolo_detector",
  "nodeName": "detector_gpu0",
  "parameters": {
    "weights_path": "/models/det1.onnx",
    "device": "0"  // GPU 0
  }
}
```

---

## 5. Chạy nhiều BA Node trong một Pipeline

### 5.1 Multi-BA cùng loại (nhiều crosslines)

```json
{
  "pipeline": [
    { "nodeType": "rtsp_src", "nodeName": "src", "parameters": {} },
    { "nodeType": "yolo_detector", "nodeName": "det", "parameters": {} },
    { "nodeType": "bytetrack", "nodeName": "tracker", "parameters": {} },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline_entrance",
      "parameters": {
        "CrossingLines": "[{\"name\":\"Entrance\",\"direction\":\"IN\",\"coordinates\":{\"start\":{\"x\":100,\"y\":400},\"end\":{\"x\":400,\"y\":400}}}]"
      }
    },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline_exit",
      "parameters": {
        "CrossingLines": "[{\"name\":\"Exit\",\"direction\":\"OUT\",\"coordinates\":{\"start\":{\"x\":500,\"y\":400},\"end\":{\"x\":800,\"y\":400}}}]"
      }
    },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline_emergency",
      "parameters": {
        "CrossingLines": "[{\"name\":\"Emergency Lane\",\"direction\":\"BOTH\",\"coordinates\":{\"start\":{\"x\":300,\"y\":100},\"end\":{\"x\":300,\"y\":700}}}]"
      }
    }
  ]
}
```

### 5.2 Multi-BA khác loại (composite analytics)

```json
{
  "solutionId": "securt_composite",
  "pipeline": [
    { "nodeType": "rtsp_src", "nodeName": "src", "parameters": {} },
    { "nodeType": "yolo_detector", "nodeName": "det", "parameters": {} },
    { "nodeType": "bytetrack", "nodeName": "tracker", "parameters": {} },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline",
      "parameters": { "CrossingLines": "${CrossingLines}" }
    },
    {
      "nodeType": "ba_jam",
      "nodeName": "jam",
      "parameters": { "JamZones": "${JamZones}" }
    },
    {
      "nodeType": "ba_stop",
      "nodeName": "stop",
      "parameters": { "StopZones": "${StopZones}" }
    },
    {
      "nodeType": "ba_loitering",
      "nodeName": "loitering",
      "parameters": { "LoiteringAreas": "${LoiteringAreas}" }
    }
  ]
}
```

### 5.3 BA OSD Auto-Attachment (reverse scan)

Khi có nhiều BA node cùng loại, OSD gắn vào **node CUỐI CÙNG** (reverse scan):

```cpp
// pipeline_builder.cpp dòng 637–679
// Reverse scan từ cuối về đầu — tìm LAST occurrence
for (int i = static_cast<int>(nodes.size()) - 1; i >= 0; --i) {
    if (nodeTypes[i] == targetBAType) {
        attachTarget = nodes[i];  // ← gắn vào BA node gần nhất phía trước
        break;
    }
}
```

```
         ba_crossline (entrance)     ba_crossline (exit)      ba_crossline (emergency)
                   │                        │                        │
                   │                        │                        │
              ba_crossline_osd ◀─────────────┘────────────────────────┘
                                          (gắn vào LAST ba_crossline)

              Nếu muốn OSD cho từng BA → khai báo nhiều OSD node trong pipeline
```

### 5.4 OSD riêng cho từng BA Node

```json
{
  "pipeline": [
    { "nodeType": "rtsp_src", "nodeName": "src", "parameters": {} },
    { "nodeType": "yolo_detector", "nodeName": "det", "parameters": {} },
    { "nodeType": "bytetrack", "nodeName": "tracker", "parameters": {} },
    {
      "nodeType": "ba_crossline",
      "nodeName": "crossline_entrance",
      "parameters": { "CrossingLines": "${CrossingLinesEntrance}" }
    },
    {
      "nodeType": "ba_crossline_osd",
      "nodeName": "crossline_entrance_osd",
      "parameters": {}  // reverse scan sẽ gắn vào crossline_entrance
    },
    {
      "nodeType": "ba_jam",
      "nodeName": "jam_zone",
      "parameters": { "JamZones": "${JamZones}" }
    },
    {
      "nodeType": "ba_jam_osd",
      "nodeName": "jam_zone_osd",
      "parameters": {}  // reverse scan gắn vào ba_jam
    },
    {
      "nodeType": "ba_stop",
      "nodeName": "stop_zone",
      "parameters": { "StopZones": "${StopZones}" }
    },
    {
      "nodeType": "ba_stop_osd",
      "nodeName": "stop_zone_osd",
      "parameters": {}
    }
  ]
}
```

### 5.5 Multi-file_des cho multi-BA branch

Khi có cả `ba_crossline_osd` VÀ `ba_loitering_osd`, builder tự tạo **file_des riêng** cho mỗi nhánh:

```cpp
// pipeline_builder.cpp dòng 681–747
if (!attachTarget && nodeConfig.nodeType == "file_des") {
    bool hasBACrosslineOSD = hasNodeType("ba_crossline_osd");
    bool hasBALoiteringOSD = hasNodeType("ba_loitering_osd");

    if (hasBACrosslineOSD && hasBALoiteringOSD) {
        // First file_des → ba_crossline_osd
        // Second file_des → ba_loitering_osd
    }
}
```

---

## 6. Hệ thống Solution Config & Parameter

### 6.1 SolutionConfig structure

**File:** `include/models/solution_config.h`

```cpp
struct SolutionConfig {
  std::string solutionId;      // "ba_crossline", "securt", ...
  std::string solutionName;
  std::string solutionType;    // "behavior_analysis", "face_detection", ...
  std::string category;        // "security", "its", "armed", ...
  std::string feature;         // "crossline", "jam", "loitering"
  bool isDefault = false;

  struct NodeConfig {
    std::string nodeType;                              // "yolo_detector", ...
    std::string nodeName;                              // Template "{instanceId}"
    std::map<std::string, std::string> parameters;    // ${...} placeholders
  };

  std::vector<NodeConfig> pipeline;   // Thứ tự build
  std::map<std::string, std::string> defaults;  // Default cho tất cả nodes
};
```

### 6.2 CreateInstanceRequest

**File:** `include/models/create_instance_request.h`

```cpp
struct CreateInstanceRequest {
  std::string name;
  std::string solution;           // solutionId
  bool persistent = false;
  int frameRateLimit = 0;
  std::string detectionSensitivity = "Low";
  int fps = 0;

  // ← Tất cả tham số động đi qua đây
  std::map<std::string, std::string> additionalParams;
};
```

### 6.3 Placeholder Resolution — `buildParameterMap()`

**File:** `src/core/pipeline_builder.cpp` (dòng 2476–2685)

```
Thứ tự resolve:
1. substituteNodeName(value, instanceId) → thay {instanceId}
2. Handler cứng cho known placeholders (RTSP_URL, FILE_PATH, RTMP_URL, ...)
3. Regex generic ${VARIABLE_NAME} → lookup req.additionalParams
4. Unresolved → giữ nguyên (SDK xử lý hoặc fail graceful)
```

```cpp
// Ví dụ placeholder resolution
"${RTSP_URL}"        → additionalParams["RTSP_URL"] hoặc additionalParams["RTSP_SRC_URL"]
"${WEIGHTS_PATH}"   → additionalParams["WEIGHTS_PATH"] > additionalParams["MODEL_PATH"]
"${MODEL_PATH}"     → PipelineBuilderModelResolver::resolveModelByName(...)
"${frameRateLimit}" → req.frameRateLimit (int → string)
"${detectionSensitivity}" → mapSensitivity(req.detectionSensitivity)
```

### 6.4 Available Solutions

**File:** `src/solutions/solution_registry.cpp`

```
Basic BA:
  ba_crossline, ba_jam, ba_stop, ba_loitering, ba_area_enter_exit,
  ba_line_counting, ba_crowding

BA với MQTT:
  ba_crossline_mqtt_default, ba_jam_mqtt_default, ba_stop_mqtt_default

Flexible I/O:
  ba_crossline_default, ba_jam_default, ba_stop_default

Composite (SecuRT):
  securt → auto-injects ba_crossline + ba_loitering + ba_stop (nếu zones tồn tại)

Detection:
  face_detection, fire_smoke_detection, obstacle_detection,
  wrong_way_detection
```

---

## 7. Luồng lắp ráp Pipeline (Build Pipeline)

```
CreateInstanceRequest
        │
        ▼
┌────────────────────────────────────────────────────────────┐
│ 1. SolutionRegistry::getSolution(solutionId)             │
│    → SolutionConfig { pipeline[], defaults{} }           │
└────────────────────────────┬───────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│ 2. loadSecuRTData()                                      │
│    → Nạp SecuRT areas/lines từ AreaManager +            │
│      SecuRTLineManager vào additionalParams              │
│    → Auto-detect hasStopZones, hasLoiteringAreas         │
└────────────────────────────┬───────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│ 3. handleMultipleSources()                               │
│    → FILE_PATHS / RTSP_URLS JSON → tạo nhiều source nodes│
│    → hasMultipleSources = true khi count > 1            │
│    → detector/tracker sẽ fan-out                          │
└────────────────────────────┬───────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│ 4. buildPipeline() — Duyệt pipeline[] theo thứ tự     │
│    ┌────────────────────────────────────────────────────┐ │
│    │ For mỗi nodeConfig trong solution.pipeline[]:    │ │
│    │                                                    │ │
│    │ 4a. buildParameterMap()                           │ │
│    │     → Resolve ${...} placeholders                 │ │
│    │                                                    │ │
│    │ 4b. createNode(nodeType)                          │ │
│    │     → Dispatch sang factory function đúng        │ │
│    │                                                    │ │
│    │ 4c. attach_to() — routing theo node type:         │ │
│    │     Multi-source? → attach_to(multipleSourceNodes)│ │
│    │     BA OSD?      → reverse scan → matching BA node│ │
│    │     Dest node?   → skip dest nodes → last producer│ │
│    │     Normal?      → attach to second-to-last node  │ │
│    │                                                    │ │
│    │ 4d. nodes.push_back(node)                          │ │
│    │     nodeTypes.push_back(nodeType)                  │ │
│    │     (parallel vectors — nodeTypes chỉ dùng lookup) │ │
│    └────────────────────────────────────────────────────┘ │
└────────────────────────────┬───────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│ 5. autoInjectOptionalNodes()                              │
│    RTMP: RTMP_URL / RTMP_DES_URL → inject rtmp_des       │
│    Screen: ENABLE_SCREEN_DES=true → inject screen_des    │
│    MQTT: MQTT_BROKER_URL + BA nodes → inject broker       │
│    SecuRT: hasStopZones → inject ba_stop                  │
│    SecuRT: hasLoiteringAreas → inject ba_loitering        │
└────────────────────────────┬───────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│ 6. Return vector<shared_ptr<cvedix_node>>                  │
│    Node graph kết nối đầy đủ, ready for pipeline->run()  │
└────────────────────────────────────────────────────────────┘
```

---

## 8. Chiến lược kết nối Node (attach_to)

### 8.1 Bảng routing kết nối

| Node type mới | Target gắn vào | Cơ chế |
|---|---|---|
| `rtsp_src` / `file_src` | — (nguồn, không ai gắn vào nó) | Initial nodes |
| `yolo_detector` | Tất cả `multipleSourceNodes` | Fan-out khi multi-source |
| `sort_track` / `sort_tracker` | Tất cả `multipleSourceNodes` | Fan-out khi multi-source |
| `bytetrack` | Node liền trước (thường là detector) | Single attach |
| `ba_crossline_osd` | **Last** `ba_crossline` | Reverse scan |
| `ba_jam_osd` | **Last** `ba_jam` | Reverse scan |
| `ba_stop_osd` | **Last** `ba_stop` | Reverse scan |
| `ba_loitering_osd` | **Last** `ba_loitering` | Reverse scan |
| `ba_area_enter_exit_osd` | **Last** `ba_area_enter_exit` | Reverse scan |
| `file_des` (normal) | Last non-dest node | Skip dest chain |
| `file_des` (multi-BA) | First → crossline_osd, Second → loitering_osd | hasNodeType() |
| `rtmp_des` (có OSD) | Last OSD node | Special handling |
| `rtmp_des` (normal) | Last non-dest node | Skip dest chain |
| `screen_des` | Last OSD / last non-dest | Fallback |
| Broker (crossline) | **First** `ba_crossline` | Forward scan |
| Broker (jam) | **First** `ba_jam` | Forward scan |
| Broker (stop) | **First** `ba_stop` | Forward scan |
| Auto-inject `ba_stop` | `sort_track` | attachTarget fallback |

### 8.2 Reverse scan cho BA OSD

```cpp
// Tìm node CUỐI CÙNG cùng loại (phía trước trong pipeline)
for (int i = nodes.size() - 1; i >= 0; --i) {
    if (nodeTypes[i] == targetBAType) {
        attachTarget = nodes[i];
        break;  // ← dừng ở occurrence gần nhất
    }
}
```

### 8.3 Forward scan cho Broker

```cpp
// Tìm node ĐẦU TIÊN cùng loại (broker chạy song song với analytics path)
for (size_t i = 0; i < nodeTypes.size(); ++i) {
    if (nodeTypes[i] == targetBAType) {
        attachTarget = nodes[i];
        break;
    }
}
```

### 8.4 Skip dest nodes

```cpp
// Dest nodes (file_des, rtmp_des, screen_des, ...) không forward frames
// Skip backward qua chain of dest nodes
for (int i = attachIndex - 1; i >= 0; --i) {
    bool nodeIsDest = (nodeTypes[i] == "file_des" || ...);
    if (!nodeIsDest) {
        attachIndex = i;
        break;
    }
}
```

---

## 9. Hướng dẫn thực hành

### 9.1 Gọi API tạo pipeline đơn (single stream)

```cpp
#include "api/omniapi.hpp"

auto api = OmniAPIFactory::create();

// Tạo crossline instance
CreateInstanceRequest req;
req.name = "Lane1Camera";
req.solution = "ba_crossline_default";
req.additionalParams["RTSP_URL"] = "rtsp://192.168.1.100/stream";
req.additionalParams["CrossingLines"] = R"([
  {
    "name": "Lane1-In",
    "color": [0, 255, 0, 255],
    "direction": "IN",
    "coordinates": {"start": {"x": 100, "y": 400}, "end": {"x": 600, "y": 400}}
  }
])";
req.additionalParams["BA_SOCKET_IP"] = "127.0.0.1";
req.additionalParams["BA_SOCKET_PORT"] = "8080";

auto result = api->createInstance(req);
```

### 9.2 Multi-stream với shared detector/tracker

```cpp
// 4 camera cùng một detector + tracker + analytics
CreateInstanceRequest req;
req.name = "MultiCameraZone";
req.solution = "ba_crossline_default";  // hoặc custom solution
req.additionalParams["RTSP_URLS"] = R"([
  {"rtsp_url": "rtsp://cam1/stream", "channel": 0, "resize_ratio": 0.6},
  {"rtsp_url": "rtsp://cam2/stream", "channel": 1, "resize_ratio": 0.6},
  {"rtsp_url": "rtsp://cam3/stream", "channel": 2, "resize_ratio": 0.6},
  {"rtsp_url": "rtsp://cam4/stream", "channel": 3, "resize_ratio": 0.6}
])";
req.additionalParams["CrossingLines"] = R"([
  {"name": "Cam1-Line", "direction": "BOTH", ...},
  {"name": "Cam2-Line", "direction": "BOTH", ...}
])";

auto result = api->createInstance(req);
```

### 9.3 Custom multi-inference solution (đăng ký vào registry)

```cpp
// Đăng ký custom solution
SolutionConfig multiHead;
multiHead.solutionId = "multi_head_analytics";
multiHead.solutionName = "Multi-Head Analytics";
multiHead.solutionType = "behavior_analysis";
multiHead.category = "security";

multiHead.pipeline = {
  {
    .nodeType = "rtsp_src",
    .nodeName = "src_{instanceId}",
    .parameters = {{"rtsp_url", "${RTSP_URL}"}}
  },
  {
    .nodeType = "yolo_detector",
    .nodeName = "person_vehicle_det_{instanceId}",
    .parameters = {{"weights_path", "${WEIGHTS_PATH}"}}
  },
  {
    .nodeType = "yolo_detector",
    .nodeName = "face_det_{instanceId}",
    .parameters = {{"weights_path", "${FACE_MODEL_PATH}"}}
  },
  {
    .nodeType = "bytetrack",
    .nodeName = "tracker_{instanceId}",
    .parameters = {
      {"track_thresh", "0.5"},
      {"track_buffer", "30"}
    }
  },
  {
    .nodeType = "ba_crossline",
    .nodeName = "crossline_{instanceId}",
    .parameters = {{"CrossingLines", "${CrossingLines}"}}
  },
  {
    .nodeType = "ba_jam",
    .nodeName = "jam_{instanceId}",
    .parameters = {{"JamZones", "${JamZones}"}}
  },
  {
    .nodeType = "ba_crossline_osd",
    .nodeName = "crossline_osd_{instanceId}",
    .parameters = {}
  },
  {
    .nodeType = "ba_jam_osd",
    .nodeName = "jam_osd_{instanceId}",
    .parameters = {}
  },
  {
    .nodeType = "ba_socket_broker",
    .nodeName = "broker_{instanceId}",
    .parameters = {
      {"BA_SOCKET_IP", "${BA_SOCKET_IP}"},
      {"BA_SOCKET_PORT", "${BA_SOCKET_PORT}"}
    }
  }
};

SolutionRegistry::getInstance().registerSolution(multiHead);
```

### 9.4 Tạo custom BA solution

```cpp
// Solution cho phép người dùng khai báo multi-crossline
SolutionConfig multiCrossline;
multiCrossline.solutionId = "multi_crossline_custom";
multiCrossline.solutionType = "behavior_analysis";

multiCrossline.pipeline = {
  {"rtsp_src", "${RTSP_URL}"},
  {"yolo_detector", "${WEIGHTS_PATH}"},
  {"bytetrack", ""},
  // User khai báo bao nhiêu crossline tùy ý
  {"ba_crossline", "${CrossingLines_Entrance}"},
  {"ba_crossline", "${CrossingLines_Exit}"},
  {"ba_crossline", "${CrossingLines_Emergency}"},
  {"ba_crossline_osd", ""},
  {"ba_socket_broker", "${BA_SOCKET_IP}:${BA_SOCKET_PORT}"},
  {"screen_des", ""},
  {"rtmp_des", "${RTMP_URL}"}
};

SolutionRegistry::getInstance().registerSolution(multiCrossline);

// User gọi với nhiều zone
CreateInstanceRequest req;
req.solution = "multi_crossline_custom";
req.additionalParams["RTSP_URL"] = "rtsp://...";
req.additionalParams["CrossingLines_Entrance"] = "[...]";
req.additionalParams["CrossingLines_Exit"] = "[...]";
req.additionalParams["CrossingLines_Emergency"] = "[...]";
```

### 9.5 SecuRT auto-injection pattern

```cpp
// SecuRT solution tự động inject BA nodes dựa trên zone data
// SolutionRegistry::initializeDefaultSolutions() lines 954–1281

CreateInstanceRequest req;
req.solution = "securt";
req.additionalParams["RTSP_URL"] = "rtsp://cam1/stream";
req.additionalParams["CrossingLines"] = "[{\"name\":\"Main Gate\"}]";
req.additionalParams["LoiteringAreas"] = "[{\"name\":\"Gate Area\"}]";
// req.additionalParams["StopZones"] = "[...]"  // → sẽ trigger ba_stop auto-injection

// Kết quả pipeline tự động:
// rtsp_src → yolo_detector → sort_track → ba_crossline
//                                          → ba_loitering (auto)
//                                          → ba_stop (auto nếu StopZones có)
//                                          → json_console_broker
//                                          → ba_crossline_osd
//                                          → screen_des
```

### 9.6 Kiểm tra pipeline graph trước khi chạy

```cpp
// Sau khi build, in ra node graph để debug
PipelineBuilder builder(req);
auto nodes = builder.buildPipeline();

std::cout << "Pipeline built with " << nodes.size() << " nodes:\n";
for (size_t i = 0; i < nodes.size(); ++i) {
    std::cout << "  [" << i << "] " << nodeTypes[i]
              << " → " << nodes[i]->getName() << "\n";
}
```

---

## Phụ lục A: File Index

| File | Mục đích |
|---|---|
| `src/core/pipeline_builder.cpp` | Main pipeline assembly (4702 dòng) |
| `src/core/pipeline_builder_source_nodes.cpp` | RTSP/File/RTMP source node factory |
| `src/core/pipeline_builder_detector_nodes.cpp` | YOLO detector node factory |
| `src/core/pipeline_builder_other_nodes.cpp` | ByteTrack, SORT, OCSort tracker factories |
| `src/core/pipeline_builder_behavior_analysis_nodes.cpp` | Tất cả BA + BA OSD node factories |
| `src/core/pipeline_builder_broker_nodes.cpp` | Tất cả broker node factories |
| `src/solutions/solution_registry.cpp` | SolutionRegistry — đăng ký ~25 solutions |
| `include/models/solution_config.h` | SolutionConfig struct definition |
| `include/models/create_instance_request.h` | CreateInstanceRequest struct |
| `include/solutions/solution_registry.h` | SolutionRegistry header |

## Phụ lục B: Environment Variables

| Variable | Tác dụng |
|---|---|
| `FORCE_CPU_INFERENCE=1` | Force CPU cho tất cả inference nodes |
| `OPENCV_DNN_BACKEND=OPENCV` | FFmpeg fallback nếu CUDA lỗi |
| `RTSP_TRANSPORT=TCP` | RTSP transport protocol |
| `CVEDIX_WITH_KAFKA=1` | Enable Kafka broker support |
| `ENABLE_SCREEN_DES=true` | Auto-inject screen destination |
| `RTSP_SRC_URL` / `RTSP_URL` | RTSP source URL |
| `RTMP_DES_URL` / `RTMP_URL` | RTMP destination URL |
