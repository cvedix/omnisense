/*
 * GStreamer NIF - Video Processor using GStreamer
 * 
 * Replaces FFmpeg with GStreamer for video encoding/decoding/conversion.
 * Provides the same API as the original FFmpeg-based NIF.
 */

#ifndef GST_NIF_H
#define GST_NIF_H

#include <erl_nif.h>
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <string.h>
#include <stdio.h>

/* Resource types */
static ErlNifResourceType *gst_encoder_resource;
static ErlNifResourceType *gst_decoder_resource;
static ErlNifResourceType *gst_converter_resource;

/* GStreamer initialized flag */
static int gst_initialized = 0;

/* Hardware platform enum */
typedef enum {
    HW_PLATFORM_SOFTWARE = 0,
    HW_PLATFORM_ROCKCHIP,
    HW_PLATFORM_VAAPI,
    HW_PLATFORM_NVIDIA
} HardwarePlatform;

/* Cached hardware platform */
static HardwarePlatform detected_platform = HW_PLATFORM_SOFTWARE;
static int platform_detected = 0;

/* Helper macros - must be before any function that uses them */
#define GST_LOG_DEBUG(msg) fprintf(stderr, "[GST-NIF] %s\n", msg)

/* Initialize GStreamer - forward declaration */
static void ensure_gst_init() {
    if (!gst_initialized) {
        gst_init(NULL, NULL);
        gst_initialized = 1;
    }
}

/* Check if a GStreamer element is available */
static int element_available(const char *element_name) {
    ensure_gst_init();
    GstElementFactory *factory = gst_element_factory_find(element_name);
    if (factory) {
        gst_object_unref(factory);
        return 1;
    }
    return 0;
}

/* Detect hardware platform */
static HardwarePlatform detect_hardware_platform() {
    if (platform_detected) {
        return detected_platform;
    }
    
    ensure_gst_init();
    
    /* Priority: Rockchip > VAAPI > NVIDIA > Software */
    if (element_available("mppvideodec") && element_available("mpph264enc")) {
        detected_platform = HW_PLATFORM_ROCKCHIP;
        GST_LOG_DEBUG("Detected Rockchip MPP hardware acceleration");
    } else if (element_available("vaapidecodebin") || element_available("vaapidecode")) {
        detected_platform = HW_PLATFORM_VAAPI;
        GST_LOG_DEBUG("Detected VAAPI hardware acceleration");
    } else if (element_available("nvdec") || element_available("nvh264dec")) {
        detected_platform = HW_PLATFORM_NVIDIA;
        GST_LOG_DEBUG("Detected NVIDIA hardware acceleration");
    } else {
        detected_platform = HW_PLATFORM_SOFTWARE;
        GST_LOG_DEBUG("Using software encoding/decoding");
    }
    
    platform_detected = 1;
    return detected_platform;
}

/* Get encoder element string based on codec and hardware */
static const char* get_encoder_element(const char *codec, HardwarePlatform platform) {
    if (strcmp(codec, "h264") == 0) {
        switch (platform) {
            case HW_PLATFORM_ROCKCHIP:
                return "mpph264enc bps=2000000 gop=30";
            case HW_PLATFORM_VAAPI:
                return "vaapih264enc bitrate=2000 keyframe-period=30";
            case HW_PLATFORM_NVIDIA:
                return "nvh264enc bitrate=2000 gop-size=30 preset=low-latency-hq";
            default:
                return "x264enc tune=zerolatency speed-preset=ultrafast bitrate=2000 key-int-max=30";
        }
    } else if (strcmp(codec, "h265") == 0 || strcmp(codec, "hevc") == 0) {
        switch (platform) {
            case HW_PLATFORM_ROCKCHIP:
                return "mpph265enc bps=1500000 gop=60";
            case HW_PLATFORM_VAAPI:
                return "vaapih265enc bitrate=1500 keyframe-period=60";
            case HW_PLATFORM_NVIDIA:
                return "nvh265enc bitrate=1500 gop-size=60 preset=hq";
            default:
                return "x265enc tune=zerolatency speed-preset=ultrafast bitrate=1500";
        }
    } else if (strcmp(codec, "mjpeg") == 0) {
        switch (platform) {
            case HW_PLATFORM_ROCKCHIP:
                return element_available("mppjpegenc") ? "mppjpegenc" : "jpegenc";
            default:
                return "jpegenc";
        }
    }
    return NULL;
}

/* Get decoder element string based on codec and hardware */
static const char* get_decoder_element(const char *codec, HardwarePlatform platform) {
    if (strcmp(codec, "h264") == 0) {
        switch (platform) {
            case HW_PLATFORM_ROCKCHIP:
                return "mppvideodec";
            case HW_PLATFORM_VAAPI:
                return "vaapidecodebin";
            case HW_PLATFORM_NVIDIA:
                return "nvdec";
            default:
                return "avdec_h264";
        }
    } else if (strcmp(codec, "hevc") == 0 || strcmp(codec, "h265") == 0) {
        switch (platform) {
            case HW_PLATFORM_ROCKCHIP:
                return "mppvideodec";
            case HW_PLATFORM_VAAPI:
                return "vaapidecodebin";
            case HW_PLATFORM_NVIDIA:
                return "nvdec";
            default:
                return "avdec_h265";
        }
    }
    return "decodebin3";
}

/* Get parse element for codec */
static const char* get_parse_element(const char *codec) {
    if (strcmp(codec, "h264") == 0) return "h264parse";
    if (strcmp(codec, "hevc") == 0 || strcmp(codec, "h265") == 0) return "h265parse";
    return "";
}

/* Encoder structure */
typedef struct {
    GstElement *pipeline;
    GstElement *appsrc;
    GstElement *encoder;
    GstElement *appsink;
    int width;
    int height;
    GstVideoFormat format;
    int gop_size;
    int64_t frame_count;
    HardwarePlatform platform;
} GstEncoderCtx;

/* Decoder structure */
typedef struct {
    GstElement *pipeline;
    GstElement *appsrc;
    GstElement *decoder;
    GstElement *convert;
    GstElement *appsink;
    int out_width;
    int out_height;
    GstVideoFormat out_format;
    int initialized;
    HardwarePlatform platform;
} GstDecoderCtx;

/* Converter structure */
typedef struct {
    GstElement *pipeline;
    GstElement *appsrc;
    GstElement *convert;
    GstElement *scale;
    GstElement *appsink;
    int in_width;
    int in_height;
    GstVideoFormat in_format;
    int out_width;
    int out_height;
    GstVideoFormat out_format;
} GstConverterCtx;

/* Helper to create error tuple */
static ERL_NIF_TERM make_error(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env, 
        enif_make_atom(env, "error"),
        enif_make_string(env, reason, ERL_NIF_LATIN1));
}

/* Helper to create ok tuple */
static ERL_NIF_TERM make_ok(ErlNifEnv *env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), value);
}

/* Convert pixel format string to GstVideoFormat */
static GstVideoFormat format_from_string(const char *format) {
    if (strcmp(format, "yuv420p") == 0 || strcmp(format, "I420") == 0)
        return GST_VIDEO_FORMAT_I420;
    if (strcmp(format, "nv12") == 0 || strcmp(format, "NV12") == 0)
        return GST_VIDEO_FORMAT_NV12;
    if (strcmp(format, "rgb24") == 0 || strcmp(format, "RGB") == 0)
        return GST_VIDEO_FORMAT_RGB;
    if (strcmp(format, "bgr24") == 0 || strcmp(format, "BGR") == 0)
        return GST_VIDEO_FORMAT_BGR;
    if (strcmp(format, "rgba") == 0 || strcmp(format, "RGBA") == 0)
        return GST_VIDEO_FORMAT_RGBA;
    if (strcmp(format, "yuyv422") == 0 || strcmp(format, "YUY2") == 0)
        return GST_VIDEO_FORMAT_YUY2;
    return GST_VIDEO_FORMAT_I420; /* default */
}

/* Get format string for caps */
static const char* format_to_string(GstVideoFormat format) {
    switch (format) {
        case GST_VIDEO_FORMAT_I420: return "I420";
        case GST_VIDEO_FORMAT_NV12: return "NV12";
        case GST_VIDEO_FORMAT_RGB: return "RGB";
        case GST_VIDEO_FORMAT_BGR: return "BGR";
        case GST_VIDEO_FORMAT_RGBA: return "RGBA";
        case GST_VIDEO_FORMAT_YUY2: return "YUY2";
        default: return "I420";
    }
}

/*
 * Create new encoder
 * new_encoder(codec, %{width, height, format, ...}) -> ref
 */
static ERL_NIF_TERM nif_new_encoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ensure_gst_init();
    
    if (argc != 2) return make_error(env, "invalid_arg_count");
    
    char codec_name[32] = {0};
    if (!enif_get_atom(env, argv[0], codec_name, sizeof(codec_name), ERL_NIF_LATIN1)) {
        return make_error(env, "invalid_codec");
    }
    
    /* Parse options map */
    ERL_NIF_TERM key, value;
    ErlNifMapIterator iter;
    int width = 640, height = 480, gop_size = 30;
    char format_str[32] = "I420";
    
    enif_map_iterator_create(env, argv[1], &iter, ERL_NIF_MAP_ITERATOR_FIRST);
    while (enif_map_iterator_get_pair(env, &iter, &key, &value)) {
        char key_str[32];
        if (enif_get_atom(env, key, key_str, sizeof(key_str), ERL_NIF_LATIN1)) {
            if (strcmp(key_str, "width") == 0) enif_get_int(env, value, &width);
            else if (strcmp(key_str, "height") == 0) enif_get_int(env, value, &height);
            else if (strcmp(key_str, "gop_size") == 0) enif_get_int(env, value, &gop_size);
            else if (strcmp(key_str, "format") == 0) 
                enif_get_atom(env, value, format_str, sizeof(format_str), ERL_NIF_LATIN1);
        }
        enif_map_iterator_next(env, &iter);
    }
    enif_map_iterator_destroy(env, &iter);
    
    /* Create encoder context */
    GstEncoderCtx *ctx = enif_alloc_resource(gst_encoder_resource, sizeof(GstEncoderCtx));
    memset(ctx, 0, sizeof(GstEncoderCtx));
    
    ctx->width = width;
    ctx->height = height;
    ctx->format = format_from_string(format_str);
    ctx->gop_size = gop_size;
    ctx->platform = detect_hardware_platform();
    
    /* Build pipeline: appsrc ! videoconvert ! encoder ! appsink */
    char pipeline_str[512];
    const char *encoder_elem;
    
    /* Use hardware-accelerated encoder when available */
    encoder_elem = get_encoder_element(codec_name, ctx->platform);
    if (encoder_elem == NULL) {
        enif_release_resource(ctx);
        return make_error(env, "unsupported_codec");
    }
    
    fprintf(stderr, "[GST-NIF] Using encoder: %s (platform: %d)\n", encoder_elem, ctx->platform);
    
    snprintf(pipeline_str, sizeof(pipeline_str),
        "appsrc name=src format=time ! "
        "video/x-raw,format=%s,width=%d,height=%d,framerate=30/1 ! "
        "videoconvert ! %s ! appsink name=sink",
        format_to_string(ctx->format), width, height, encoder_elem);
    
    GError *error = NULL;
    ctx->pipeline = gst_parse_launch(pipeline_str, &error);
    if (error) {
        GST_LOG_DEBUG(error->message);
        g_error_free(error);
        enif_release_resource(ctx);
        return make_error(env, "pipeline_creation_failed");
    }
    
    ctx->appsrc = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "src");
    ctx->appsink = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "sink");
    
    /* Configure appsink */
    g_object_set(ctx->appsink, "emit-signals", FALSE, "sync", FALSE, NULL);
    
    /* Start pipeline */
    gst_element_set_state(ctx->pipeline, GST_STATE_PLAYING);
    
    ERL_NIF_TERM ref = enif_make_resource(env, ctx);
    enif_release_resource(ctx);
    
    return ref;
}

/*
 * Create new decoder
 * new_decoder(codec, out_width, out_height, out_format, pad) -> ref
 */
static ERL_NIF_TERM nif_new_decoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ensure_gst_init();
    
    if (argc != 5) return make_error(env, "invalid_arg_count");
    
    char codec_name[32] = {0};
    int out_width, out_height, pad;
    char out_format_str[32] = {0};
    
    if (!enif_get_atom(env, argv[0], codec_name, sizeof(codec_name), ERL_NIF_LATIN1) ||
        !enif_get_int(env, argv[1], &out_width) ||
        !enif_get_int(env, argv[2], &out_height) ||
        !enif_get_atom(env, argv[3], out_format_str, sizeof(out_format_str), ERL_NIF_LATIN1) ||
        !enif_get_int(env, argv[4], &pad)) {
        return make_error(env, "invalid_args");
    }
    
    GstDecoderCtx *ctx = enif_alloc_resource(gst_decoder_resource, sizeof(GstDecoderCtx));
    memset(ctx, 0, sizeof(GstDecoderCtx));
    
    ctx->out_width = out_width > 0 ? out_width : 640;
    ctx->out_height = out_height > 0 ? out_height : 480;
    ctx->out_format = format_from_string(out_format_str);
    ctx->platform = detect_hardware_platform();
    
    /* Use hardware-accelerated decoder when available */
    const char *decoder_elem = get_decoder_element(codec_name, ctx->platform);
    const char *parse_elem = get_parse_element(codec_name);
    
    if (strlen(parse_elem) == 0 && strcmp(codec_name, "h264") != 0 && strcmp(codec_name, "hevc") != 0) {
        enif_release_resource(ctx);
        return make_error(env, "unsupported_codec");
    }
    
    fprintf(stderr, "[GST-NIF] Using decoder: %s (platform: %d)\n", decoder_elem, ctx->platform);
    
    char pipeline_str[512];
    snprintf(pipeline_str, sizeof(pipeline_str),
        "appsrc name=src format=time ! %s ! %s ! "
        "videoconvert ! videoscale ! "
        "video/x-raw,format=%s,width=%d,height=%d ! "
        "appsink name=sink",
        parse_elem, decoder_elem,
        format_to_string(ctx->out_format), ctx->out_width, ctx->out_height);
    
    GError *error = NULL;
    ctx->pipeline = gst_parse_launch(pipeline_str, &error);
    if (error) {
        GST_LOG_DEBUG(error->message);
        g_error_free(error);
        enif_release_resource(ctx);
        return make_error(env, "pipeline_creation_failed");
    }
    
    ctx->appsrc = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "src");
    ctx->appsink = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "sink");
    
    g_object_set(ctx->appsink, "emit-signals", FALSE, "sync", FALSE, NULL);
    
    gst_element_set_state(ctx->pipeline, GST_STATE_PLAYING);
    ctx->initialized = 1;
    
    ERL_NIF_TERM ref = enif_make_resource(env, ctx);
    enif_release_resource(ctx);
    
    return ref;
}

/*
 * Create new converter
 */
static ERL_NIF_TERM nif_new_converter(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ensure_gst_init();
    
    if (argc != 7) return make_error(env, "invalid_arg_count");
    
    int in_width, in_height, out_width, out_height, pad;
    char in_format_str[32], out_format_str[32];
    
    if (!enif_get_int(env, argv[0], &in_width) ||
        !enif_get_int(env, argv[1], &in_height) ||
        !enif_get_atom(env, argv[2], in_format_str, sizeof(in_format_str), ERL_NIF_LATIN1) ||
        !enif_get_int(env, argv[3], &out_width) ||
        !enif_get_int(env, argv[4], &out_height) ||
        !enif_get_atom(env, argv[5], out_format_str, sizeof(out_format_str), ERL_NIF_LATIN1) ||
        !enif_get_int(env, argv[6], &pad)) {
        return make_error(env, "invalid_args");
    }
    
    GstConverterCtx *ctx = enif_alloc_resource(gst_converter_resource, sizeof(GstConverterCtx));
    memset(ctx, 0, sizeof(GstConverterCtx));
    
    ctx->in_width = in_width;
    ctx->in_height = in_height;
    ctx->in_format = format_from_string(in_format_str);
    ctx->out_width = out_width > 0 ? out_width : in_width;
    ctx->out_height = out_height > 0 ? out_height : in_height;
    ctx->out_format = format_from_string(out_format_str);
    
    char pipeline_str[512];
    snprintf(pipeline_str, sizeof(pipeline_str),
        "appsrc name=src format=time ! "
        "video/x-raw,format=%s,width=%d,height=%d ! "
        "videoconvert ! videoscale ! "
        "video/x-raw,format=%s,width=%d,height=%d ! "
        "appsink name=sink",
        format_to_string(ctx->in_format), in_width, in_height,
        format_to_string(ctx->out_format), ctx->out_width, ctx->out_height);
    
    GError *error = NULL;
    ctx->pipeline = gst_parse_launch(pipeline_str, &error);
    if (error) {
        g_error_free(error);
        enif_release_resource(ctx);
        return make_error(env, "pipeline_creation_failed");
    }
    
    ctx->appsrc = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "src");
    ctx->appsink = gst_bin_get_by_name(GST_BIN(ctx->pipeline), "sink");
    
    g_object_set(ctx->appsink, "emit-signals", FALSE, "sync", FALSE, NULL);
    gst_element_set_state(ctx->pipeline, GST_STATE_PLAYING);
    
    ERL_NIF_TERM ref = enif_make_resource(env, ctx);
    enif_release_resource(ctx);
    
    return ref;
}

/*
 * Encode a frame
 */
static ERL_NIF_TERM nif_encode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) return make_error(env, "invalid_arg_count");
    
    GstEncoderCtx *ctx;
    if (!enif_get_resource(env, argv[0], gst_encoder_resource, (void**)&ctx)) {
        return make_error(env, "invalid_resource");
    }
    
    ErlNifBinary input;
    if (!enif_inspect_binary(env, argv[1], &input)) {
        return make_error(env, "invalid_input");
    }
    
    unsigned long pts;
    if (!enif_get_ulong(env, argv[2], &pts)) {
        return make_error(env, "invalid_pts");
    }
    
    /* Create buffer and push to appsrc */
    GstBuffer *buffer = gst_buffer_new_allocate(NULL, input.size, NULL);
    gst_buffer_fill(buffer, 0, input.data, input.size);
    GST_BUFFER_PTS(buffer) = pts;
    GST_BUFFER_DURATION(buffer) = GST_SECOND / 30;
    
    GstFlowReturn ret = gst_app_src_push_buffer(GST_APP_SRC(ctx->appsrc), buffer);
    if (ret != GST_FLOW_OK) {
        return make_error(env, "push_failed");
    }
    
    /* Pull encoded packets */
    ERL_NIF_TERM packets = enif_make_list(env, 0);
    GstSample *sample;
    
    while ((sample = gst_app_sink_try_pull_sample(GST_APP_SINK(ctx->appsink), 0)) != NULL) {
        GstBuffer *out_buf = gst_sample_get_buffer(sample);
        GstMapInfo map;
        
        if (gst_buffer_map(out_buf, &map, GST_MAP_READ)) {
            ERL_NIF_TERM data_term;
            unsigned char *bin = enif_make_new_binary(env, map.size, &data_term);
            memcpy(bin, map.data, map.size);
            
            /* Check if keyframe */
            gboolean is_keyframe = !GST_BUFFER_FLAG_IS_SET(out_buf, GST_BUFFER_FLAG_DELTA_UNIT);
            
            ERL_NIF_TERM packet = enif_make_tuple4(env,
                data_term,
                enif_make_int64(env, GST_BUFFER_DTS(out_buf)),
                enif_make_int64(env, GST_BUFFER_PTS(out_buf)),
                enif_make_atom(env, is_keyframe ? "true" : "false"));
            
            packets = enif_make_list_cell(env, packet, packets);
            gst_buffer_unmap(out_buf, &map);
        }
        gst_sample_unref(sample);
    }
    
    ctx->frame_count++;
    return packets;
}

/*
 * Decode a packet
 */
static ERL_NIF_TERM nif_decode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 4) return make_error(env, "invalid_arg_count");
    
    GstDecoderCtx *ctx;
    if (!enif_get_resource(env, argv[0], gst_decoder_resource, (void**)&ctx)) {
        return make_error(env, "invalid_resource");
    }
    
    ErlNifBinary input;
    if (!enif_inspect_binary(env, argv[1], &input)) {
        return make_error(env, "invalid_input");
    }
    
    unsigned long pts, dts;
    if (!enif_get_ulong(env, argv[2], &pts) ||
        !enif_get_ulong(env, argv[3], &dts)) {
        return make_error(env, "invalid_timestamps");
    }
    
    /* Push to decoder */
    GstBuffer *buffer = gst_buffer_new_allocate(NULL, input.size, NULL);
    gst_buffer_fill(buffer, 0, input.data, input.size);
    GST_BUFFER_PTS(buffer) = pts;
    GST_BUFFER_DTS(buffer) = dts;
    
    gst_app_src_push_buffer(GST_APP_SRC(ctx->appsrc), buffer);
    
    /* Pull decoded frames */
    ERL_NIF_TERM frames = enif_make_list(env, 0);
    GstSample *sample;
    
    while ((sample = gst_app_sink_try_pull_sample(GST_APP_SINK(ctx->appsink), 0)) != NULL) {
        GstBuffer *out_buf = gst_sample_get_buffer(sample);
        GstMapInfo map;
        
        if (gst_buffer_map(out_buf, &map, GST_MAP_READ)) {
            ERL_NIF_TERM data_term;
            unsigned char *bin = enif_make_new_binary(env, map.size, &data_term);
            memcpy(bin, map.data, map.size);
            
            ERL_NIF_TERM frame = enif_make_tuple3(env,
                data_term,
                enif_make_int(env, ctx->out_width),
                enif_make_int(env, ctx->out_height));
            
            frames = enif_make_list_cell(env, frame, frames);
            gst_buffer_unmap(out_buf, &map);
        }
        gst_sample_unref(sample);
    }
    
    return frames;
}

/*
 * Convert a frame
 */
static ERL_NIF_TERM nif_convert(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) return make_error(env, "invalid_arg_count");
    
    GstConverterCtx *ctx;
    if (!enif_get_resource(env, argv[0], gst_converter_resource, (void**)&ctx)) {
        return make_error(env, "invalid_resource");
    }
    
    ErlNifBinary input;
    if (!enif_inspect_binary(env, argv[1], &input)) {
        return make_error(env, "invalid_input");
    }
    
    GstBuffer *buffer = gst_buffer_new_allocate(NULL, input.size, NULL);
    gst_buffer_fill(buffer, 0, input.data, input.size);
    gst_app_src_push_buffer(GST_APP_SRC(ctx->appsrc), buffer);
    
    /* Pull converted frame */
    GstSample *sample = gst_app_sink_try_pull_sample(GST_APP_SINK(ctx->appsink), GST_SECOND);
    if (!sample) {
        return make_error(env, "no_output");
    }
    
    GstBuffer *out_buf = gst_sample_get_buffer(sample);
    GstMapInfo map;
    ERL_NIF_TERM result;
    
    if (gst_buffer_map(out_buf, &map, GST_MAP_READ)) {
        ERL_NIF_TERM data_term;
        unsigned char *bin = enif_make_new_binary(env, map.size, &data_term);
        memcpy(bin, map.data, map.size);
        
        result = enif_make_tuple3(env,
            data_term,
            enif_make_int(env, ctx->out_width),
            enif_make_int(env, ctx->out_height));
        
        gst_buffer_unmap(out_buf, &map);
    } else {
        result = make_error(env, "map_failed");
    }
    
    gst_sample_unref(sample);
    return result;
}

/*
 * Flush encoder
 */
static ERL_NIF_TERM nif_flush_encoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) return make_error(env, "invalid_arg_count");
    
    GstEncoderCtx *ctx;
    if (!enif_get_resource(env, argv[0], gst_encoder_resource, (void**)&ctx)) {
        return make_error(env, "invalid_resource");
    }
    
    gst_app_src_end_of_stream(GST_APP_SRC(ctx->appsrc));
    
    /* Pull remaining packets */
    ERL_NIF_TERM packets = enif_make_list(env, 0);
    GstSample *sample;
    
    while ((sample = gst_app_sink_try_pull_sample(GST_APP_SINK(ctx->appsink), GST_SECOND / 10)) != NULL) {
        GstBuffer *out_buf = gst_sample_get_buffer(sample);
        GstMapInfo map;
        
        if (gst_buffer_map(out_buf, &map, GST_MAP_READ)) {
            ERL_NIF_TERM data_term;
            unsigned char *bin = enif_make_new_binary(env, map.size, &data_term);
            memcpy(bin, map.data, map.size);
            
            gboolean is_keyframe = !GST_BUFFER_FLAG_IS_SET(out_buf, GST_BUFFER_FLAG_DELTA_UNIT);
            
            ERL_NIF_TERM packet = enif_make_tuple4(env,
                data_term,
                enif_make_int64(env, GST_BUFFER_DTS(out_buf)),
                enif_make_int64(env, GST_BUFFER_PTS(out_buf)),
                enif_make_atom(env, is_keyframe ? "true" : "false"));
            
            packets = enif_make_list_cell(env, packet, packets);
            gst_buffer_unmap(out_buf, &map);
        }
        gst_sample_unref(sample);
    }
    
    return packets;
}

/*
 * Flush decoder
 */
static ERL_NIF_TERM nif_flush_decoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) return make_error(env, "invalid_arg_count");
    
    GstDecoderCtx *ctx;
    if (!enif_get_resource(env, argv[0], gst_decoder_resource, (void**)&ctx)) {
        return make_error(env, "invalid_resource");
    }
    
    gst_app_src_end_of_stream(GST_APP_SRC(ctx->appsrc));
    
    ERL_NIF_TERM frames = enif_make_list(env, 0);
    GstSample *sample;
    
    while ((sample = gst_app_sink_try_pull_sample(GST_APP_SINK(ctx->appsink), GST_SECOND / 10)) != NULL) {
        GstBuffer *out_buf = gst_sample_get_buffer(sample);
        GstMapInfo map;
        
        if (gst_buffer_map(out_buf, &map, GST_MAP_READ)) {
            ERL_NIF_TERM data_term;
            unsigned char *bin = enif_make_new_binary(env, map.size, &data_term);
            memcpy(bin, map.data, map.size);
            
            ERL_NIF_TERM frame = enif_make_tuple3(env,
                data_term,
                enif_make_int(env, ctx->out_width),
                enif_make_int(env, ctx->out_height));
            
            frames = enif_make_list_cell(env, frame, frames);
            gst_buffer_unmap(out_buf, &map);
        }
        gst_sample_unref(sample);
    }
    
    return frames;
}

/* Resource destructors */
static void free_encoder(ErlNifEnv *env, void *obj) {
    GstEncoderCtx *ctx = (GstEncoderCtx *)obj;
    if (ctx->pipeline) {
        gst_element_set_state(ctx->pipeline, GST_STATE_NULL);
        gst_object_unref(ctx->pipeline);
    }
}

static void free_decoder(ErlNifEnv *env, void *obj) {
    GstDecoderCtx *ctx = (GstDecoderCtx *)obj;
    if (ctx->pipeline) {
        gst_element_set_state(ctx->pipeline, GST_STATE_NULL);
        gst_object_unref(ctx->pipeline);
    }
}

static void free_converter(ErlNifEnv *env, void *obj) {
    GstConverterCtx *ctx = (GstConverterCtx *)obj;
    if (ctx->pipeline) {
        gst_element_set_state(ctx->pipeline, GST_STATE_NULL);
        gst_object_unref(ctx->pipeline);
    }
}

/*
 * Detect hardware capabilities
 * Returns: :rockchip | :vaapi | :nvidia | :software
 */
static ERL_NIF_TERM nif_detect_hardware_caps(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ensure_gst_init();
    HardwarePlatform platform = detect_hardware_platform();
    
    const char *platform_name;
    switch (platform) {
        case HW_PLATFORM_ROCKCHIP: platform_name = "rockchip"; break;
        case HW_PLATFORM_VAAPI: platform_name = "vaapi"; break;
        case HW_PLATFORM_NVIDIA: platform_name = "nvidia"; break;
        default: platform_name = "software"; break;
    }
    
    return enif_make_atom(env, platform_name);
}

/* NIF function table */
static ErlNifFunc nif_funcs[] = {
    {"new_encoder", 2, nif_new_encoder},
    {"new_decoder", 5, nif_new_decoder},
    {"new_converter", 7, nif_new_converter},
    {"encode", 3, nif_encode, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"decode", 4, nif_decode, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"convert", 2, nif_convert, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"flush_encoder", 1, nif_flush_encoder, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"flush_decoder", 1, nif_flush_decoder, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"detect_hardware_caps", 0, nif_detect_hardware_caps}
};

/* NIF load callback */
static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    gst_encoder_resource = enif_open_resource_type(
        env, NULL, "GstEncoder", free_encoder, ERL_NIF_RT_CREATE, NULL);
    gst_decoder_resource = enif_open_resource_type(
        env, NULL, "GstDecoder", free_decoder, ERL_NIF_RT_CREATE, NULL);
    gst_converter_resource = enif_open_resource_type(
        env, NULL, "GstConverter", free_converter, ERL_NIF_RT_CREATE, NULL);
    
    return 0;
}

ERL_NIF_INIT(Elixir.TProNVR.AV.VideoProcessor.NIF, nif_funcs, load, NULL, NULL, NULL)

#endif /* GST_NIF_H */
