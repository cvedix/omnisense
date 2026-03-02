ARCH := $(or $(TARGET_ARCH), $(shell uname -m))
OS := $(or $(TARGET_OS), $(shell uname -s))
ABI ?= gnu

VERSION := 0.2.0
FFMPEG_VERSION := 7.1.1

TEMP ?= $(HOME)/.cache
FFMPEG_DIR ?= $(TEMP)/cvr/$(VERSION)/$(ARCH)/ffmpeg-$(FFMPEG_VERSION)
PRECOMPILED_FFMPEG_LINK ?= https://github.com/cvedix/cvr_precompiled/releases/download/v$(VERSION)/ffmpeg-$(OS)-$(ARCH)-$(FFMPEG_VERSION).tar.xz
PRECOMPILED_FFMPEG_NAME ?= ffmpeg-linux-$(ARCH)-$(FFMPEG_VERSION).tar.xz

PRECOMPILED = false

DIR := c_src
PRIV_DIR := $(MIX_APP_PATH)/priv
VIDEO_PROCESSOR_SO := $(PRIV_DIR)/libvideoprocessor.so
CAMERA_CAPTURE_SO := $(PRIV_DIR)/libcameracapture.so



# uncomment to compile with debug logs
# DEBUG_LOGS = -DNVR_DEBUG=1

COMMON_HEADERS = $(DIR)/encoder.h $(DIR)/decoder.h $(DIR)/video_converter.h $(DIR)/utils.h
COMMON_SOURCES = $(DIR)/encoder.c $(DIR)/decoder.c $(DIR)/video_converter.c $(DIR)/utils.c

HEADERS = $(DIR)/video_processor.h $(COMMON_HEADERS)
SOURCES = $(DIR)/video_processor.c $(COMMON_SOURCES)

CAMERA_CAPTURE_HEADERS = $(DIR)/camera/camera_capture.h $(COMMON_HEADERS)
CAMERA_CAPTURE_SOURCES = $(DIR)/camera/camera_capture.c $(COMMON_SOURCES)

CFLAGS += $(DEBUG_LOGS) -fPIC -shared

CFLAGS += -fPIC -shared
IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) $$(pkg-config --cflags libavcodec libavutil libswscale libavdevice libavformat)
LDFLAGS = $$(pkg-config --libs libavcodec libavutil libswscale libavdevice libavformat)

# Precompiled FFmpeg - disabled by default, use system FFmpeg
# To enable precompiled, run: make PRECOMPILED=true
# ifneq (,$(filter $(OS),linux Linux))
# 	ifeq ($(ABI),gnu)
# 		ifneq (,$(filter $(ARCH),x86_64 armv7l arm aarch64))
# 			PRECOMPILED = true
# 			IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) -I$(FFMPEG_DIR)/include
# 			LDFLAGS = -L$(PRIV_DIR) -lavcodec -lavutil -lswscale -lavdevice -lavformat -Wl,-rpath=\\$$ORIGIN
# 		endif
# 	endif
# endif

#Flags for MacOS
ifeq ($(OS),Darwin)
   	IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale libavdevice libavformat)
   	LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale libavdevice libavformat)
   	CFLAGS += -undefined dynamic_lookup
endif

# Flags for Fedora
ifneq ($(PRECOMPILED),true)
	ifneq (,$(wildcard /etc/fedora-release))
		IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale)
		LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale)
	endif
endif

all: download_ffmpeg $(VIDEO_PROCESSOR_SO) $(CAMERA_CAPTURE_SO)

download_ffmpeg:
	@if [ $(PRECOMPILED) = true ] && [ ! -d $(FFMPEG_DIR) ]; then \
		echo "Downloading precompiled ffmpeg..."; \
		mkdir -p $(TEMP); \
		mkdir -p $(FFMPEG_DIR); \
		curl -L $(PRECOMPILED_FFMPEG_LINK) -o $(TEMP)/$(PRECOMPILED_FFMPEG_NAME); \
		tar -xf $(TEMP)/$(PRECOMPILED_FFMPEG_NAME) -C $(FFMPEG_DIR); \
	fi

$(VIDEO_PROCESSOR_SO): $(HEADERS) $(SOURCES)
	mkdir -p $(PRIV_DIR);

	@if [ $(PRECOMPILED) = true ]; then \
		cp -f $(FFMPEG_DIR)/lib/*.so* $(PRIV_DIR)/; \
	fi
	$(CC) $(CFLAGS) $(IFLAGS) $(LFLAGS) $(SOURCES) -o $(VIDEO_PROCESSOR_SO) $(LDFLAGS)

$(CAMERA_CAPTURE_SO): $(CAMERA_CAPTURE_HEADERS) $(CAMERA_CAPTURE_SOURCES)
	@if [ $(PRECOMPILED) = true ]; then \
		cp -f $(FFMPEG_DIR)/lib/*.so* $(PRIV_DIR)/; \
	fi
	
	$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -I$(DIR) $$(pkg-config --cflags libavcodec libavutil libswscale libavdevice libavformat) $(LFLAGS) $(CAMERA_CAPTURE_SOURCES) -o $(CAMERA_CAPTURE_SO) $$(pkg-config --libs libavcodec libavutil libswscale libavdevice libavformat)
	@rm -f $(PRIV_DIR)/libav*.so $(PRIV_DIR)/libsw*.so
	@rm -f $(PRIV_DIR)/libav*.so.*.* $(PRIV_DIR)/libsw*.so.*.*





# ============================================================
# GStreamer NIF (DEFAULT - better hardware acceleration)
# Build with FFmpeg: make USE_FFMPEG=true
# ============================================================

GST_NIF_SO := $(PRIV_DIR)/libvideoprocessor.so
GST_SOURCES := $(DIR)/gst/gst_nif.c
GST_IFLAGS := -I$(ERTS_INCLUDE_DIR) -I$(DIR) $$(pkg-config --cflags gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0)
GST_LDFLAGS := $$(pkg-config --libs gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0)

# Default to GStreamer unless USE_FFMPEG is set
ifndef USE_FFMPEG
USE_GSTREAMER := true
VIDEO_PROCESSOR_SO := $(GST_NIF_SO)
SOURCES := $(GST_SOURCES)
IFLAGS := $(GST_IFLAGS)
LDFLAGS := $(GST_LDFLAGS)
endif

gst: $(PRIV_DIR)
	@echo "Building GStreamer NIF..."
	$(CC) -fPIC -shared $(GST_IFLAGS) $(GST_SOURCES) -o $(GST_NIF_SO) $(GST_LDFLAGS)
	@echo "GStreamer NIF built: $(GST_NIF_SO)"

$(PRIV_DIR):
	@mkdir -p $(PRIV_DIR)

format:
	clang-format -i $(DIR)/*

clean:
	@rm -f $(TEMP)/$(PRECOMPILED_FFMPEG_NAME)
	@rm -rf $(TEMP)/cvr/$(VERSION)
	@rm -rf $(PRIV_DIR)/*


.PHONY: format gst

