<template>
    <ECol
        v-resize-observer="handleResize"
        class="dashboard-viewer e-h-full e-p-0 overflow-hidden"
    >
        <ERow
            v-if="showTopMenu"
            ref="topMenu"
            justify="between"
            align-content="start"
            class="top-bar dark:bg-black"
        >
            <ECol class="e-p-0" cols="5">
                <ERow>
                    <select
                        :value="device.id"
                        id="device_form_id"
                        name="devices"
                        class="text-xs sm:text-sm md:text-base dark:bg-black dark:placeholder-white/60 dark:text-white dark:hover:bg-green-800 e-border-transparent"
                        @input="
                            $emit('switch_device', {
                                device: $event.target.value,
                            })
                        "
                    >
                        <option
                            v-for="device in devices"
                            :key="device.id"
                            :value="device.id"
                        >
                            {{ device.name }}
                        </option>
                    </select>
                    <select
                        :value="stream"
                        name="streams"
                        class="text-xs sm:text-sm md:text-base dark:bg-black dark:placeholder-white/60 dark:text-white dark:hover:bg-green-800 e-border-transparent"
                        @input="
                            $emit('switch_stream', {
                                stream: $event.target.value,
                            })
                        "
                    >
                        <option
                            v-for="stream in streams"
                            :key="stream.value"
                            :value="stream.value"
                        >
                            {{ stream.name }}
                        </option>
                    </select>
                </ERow>
            </ECol>
            <ETooltip v-if="liveViewEnabled" position="bottom" text="Go live">
                <button
                    class="text-xs sm:text-sm md:text-base dark:bg-black dark:border-green-700 e-h-full text-white dark:text-white px-2 sm:px-4 flex items-center dark:hover:bg-green-800"
                    @click="$emit('load-recording', { timestamp: null })"
                >
                    <span class="">Live</span>
                    <div v-if="!startDate" class="ml-2">
                        <EPulsatingDot :size="12" color="#c5393d" />
                    </div>
                </button>
            </ETooltip>
            <ECol class="e-p-0" cols="5" align-self="stretch">
                <ERow
                    class="right-buttons e-h-full"
                    align-content="stretch"
                    justify="end"
                >
                    <ETooltip
                        v-if="liveViewEnabled"
                        position="bottom"
                        text="Download current snapshot"
                    >
                        <button
                            class="dark:bg-black dark:border-green-700 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-green-800"
                            @click="downloadSnapshot"
                        >
                            <EIcon icon="camera" size="xl" class="e-mt-1" />
                        </button>
                    </ETooltip>
                    <ETooltip position="bottom" text="Download footage">
                        <button
                            class="dark:bg-black dark:border-green-700 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-green-800"
                            @click="$emit('show-download-modal')"
                        >
                            <EIcon icon="download" size="xl" class="e-mt-1" />
                        </button>
                    </ETooltip>
                </ERow>
            </ECol>
        </ERow>
        <ELayout ref="mainLayout" :height="height" class="w-full h-full flex flex-col justify-center items-center">
            <template #main>
                <!-- stats  -->
                <div
                    v-if="isStreamShown"
                    class="absolute z-10 top-5 left-5 max-w-sm bg-slate-800/70 rounded-2xl shadow-xl p-2"
                >
                    <div
                        class="grid grid-cols-1 sm:grid-cols-2 gap-x-1 gap-y-1"
                    >
                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Resolution</span
                            >
                            <span
                                id="resolution"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.resolution }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Bitrate</span
                            >
                            <span
                                id="bitrate"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ bitrate }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Bandwidth</span
                            >
                            <span
                                id="bandwidth"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.bandwidth }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Available Levels</span
                            >
                            <span
                                id="frameRate"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.availableLevels }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Total Video Frames</span
                            >
                            <span
                                id="totalVideoFrames"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.totalVideoFrames }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Corrupted Frames</span
                            >
                            <span
                                id="decodedFrames"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.corruptedFrames }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Dropped Frames</span
                            >
                            <span
                                id="droppedFrames"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.droppedFrames }}</span
                            >
                        </div>

                        <!-- Codec -->
                        <div class="flex flex-col p-1 sm:p-2">
                            <span class="text-xs sm:text-sm text-white/80 font-medium mb-0"
                                >Codec</span
                            >
                            <span
                                id="codec"
                                class="text-sm sm:text-base text-white font-semibold"
                                >{{ stats.codec }}</span
                            >
                        </div>
                    </div>
                </div>
                <EVideoPlayer
                    id="main"
                    v-if="liveViewEnabled"
                    ref="videoPlayer"
                    class="w-full h-full object-contain bg-black flex-1"
                    :sources="isLiveStream ? [] : [
                        {
                            src: url,
                        },
                    ]"
                    :is-hls="!isLiveStream"
                    is-zoomable
                    :pause-on-click="false"
                    :video-options="videoOptions"
                    :hls-options="{
                        manifestLoadingTimeOut: 60000,
                    }"
                />

                <div
                    v-else
                    class="relative text-lg rounded-tr rounded-tl text-center bg-gray-200 dark:text-gray-200 w-full h-full dark:bg-gray-400 flex justify-center items-center d-flex"
                >
                    Device is not recording, live view is not available
                </div>
            </template>

            <template #bottom-right>
                <ECol>
                    <div class="mb-2">
                        <button
                            class="dark:bg-black dark:border-green-700 text-white dark:text-white px-3.5 e-py-2.5 flex items-center dark:hover:bg-green-800"
                            @click="openStatsTab"
                        >
                            <i class="fa-solid fa-sliders"></i>
                        </button>
                    </div>

                    <button
                        class="dark:bg-black dark:border-green-700 text-white dark:text-white px-3 e-py-1.5 flex items-center dark:hover:bg-green-800"
                        @click="toggleFullscreen"
                    >
                        <EIcon
                            :icon="isFullScreen ? 'minimize' : 'maximize'"
                            size="xl"
                            class="e-mt-1"
                        />
                    </button>
                </ECol>
            </template>
        </ELayout>
        <Timeline
            v-if="showTimeline"
            ref="timeline"
            :segments="segments"
            @run-clicked="$emit('load-recording', $event)"
        />
    </ECol>
</template>

<script>
import { defineComponent, isProxy, toRaw } from "vue";
import Timeline from "./Timeline.vue";
import { makeFullScreen, exitFullScreen } from "@evercam/ui/vue3";
import Hls from "hls.js";
import { Socket } from "phoenix";

export default defineComponent({
    props: {
        url: {
            type: String,
            default: "",
        },
        token: {
            type: String,
            default: "",
        },
        poster: {
            type: String,
            default: "",
        },
        segments: {
            type: Array,
            default: () => {
                [];
            },
        },
        devices: {
            type: Array,
            default: () => {
                [];
            },
        },
        streams: {
            type: Array,
            default: () => {
                [];
            },
        },
        stream: {
            type: String,
            default: "",
        },
        device: {
            type: Object,
            default: () => ({}),
        },
        liveViewEnabled: {
            type: Boolean,
            default: false,
        },
        startDate: {
            type: String,
            default: null,
        },
        showTimeline: {
            type: Boolean,
            default: true,
        },
        fitContainer: {
            type: Boolean,
            default: false,
        },
        showTopMenu: {
            type: Boolean,
            default: true,
        },
    },
    components: {
        Timeline,
    },
    computed: {
        isLiveStream() {
            return this.liveViewEnabled && !this.startDate;
        },
        videoOptions() {
            return {
                autoplay: true,
                muted: true,
                controls: false,
                poster: this.poster,
            };
        },
    },
    watch: {
        url(value) {
            this.$nextTick(() => {
                this.startStreaming(value);
            });
        },
        liveViewEnabled(value) {
            if (value) {
                this.$nextTick(() => {
                    this.startStreaming(this.url);
                });
            }
        }
    },

    mounted() {
        this.startStreaming(this.url);
        this.$nextTick(() => this.handleResize());
        window.addEventListener('resize', this.handleResize);
    },
    beforeUnmount() {
        this.cleanupWebRTC();
        window.removeEventListener('resize', this.handleResize);
    },
    data() {
        return {
            height: "calc(100vh - 150px)",
            navElement: null,
            isFullScreen: false,
            isStreamShown: false,
            interval: null,
            stats: {
                availableLevels: 0,
                resolution: "",
                bandwidth: "", // rate at which a fragment finish downloading
                totalVideoFrames: 0,
                corruptedFrames: 0,
                droppedFrames: 0,
                codec: "",
                bitrate: "",
            },
        };
    },
    methods: {
        handleResize() {
            if (this.fitContainer) {
                this.height = "100%";
                return;
            }
            // Use window.innerHeight for reliable viewport-based calculation
            const viewportH = window.innerHeight;
            const navH = document.getElementById('main-nav')?.offsetHeight ?? 0;
            const topMenuH = this.$refs.topMenu?.$el?.offsetHeight ?? 0;
            const timelineH = this.$refs.timeline?.$el?.offsetHeight ?? 0;
            this.height = `${Math.max(viewportH - navH - topMenuH - timelineH, 200)}px`;
        },
        getNavHeight() {
            if (!this.navElement) {
                this.navElement = document.getElementById("main-nav");
            }

            return this.navElement?.clientHeight ?? 0;
        },
        downloadSnapshot(event) {
            const player = this.$refs.videoPlayer?.$refs.player;
            var canvas = document.createElement("canvas");

            if (!player) {
                return;
            }

            canvas.width = player.videoWidth;
            canvas.height = player.videoHeight;
            canvas
                .getContext("2d")
                .drawImage(player, 0, 0, canvas.width, canvas.height);

            const dataUri = canvas.toDataURL("image/jpeg", 0.7);

            const timestampOfRequest = new Date()
                .toString()
                .split("GMT")[0]
                .trim();

            const link = document.createElement("a");
            link.style.display = "none";
            link.download = `${this.device.name}_${timestampOfRequest}_${this.stream}.png`;
            link.href = dataUri;

            document.body.appendChild(link);
            link.click();

            document.body.removeChild(link);
            canvas
                .getContext("2d")
                .clearRect(0, 0, canvas.width, canvas.height);
        },
        async toggleFullscreen() {
            this.isFullScreen = !this.isFullScreen;
            if (this.isFullScreen) {
                await makeFullScreen(this.$refs.mainLayout.$el);
                setTimeout(
                    () => (this.height = `${window.screen.height}px`),
                    200,
                );
            } else {
                exitFullScreen();
            }
        },
        openStatsTab() {
            this.isStreamShown = !this.isStreamShown;
        },
        cleanupWebRTC() {
            if (this._webrtcChannel) {
                this._webrtcChannel.leave();
                this._webrtcChannel = null;
            }
            if (this._webrtcPc) {
                this._webrtcPc.close();
                this._webrtcPc = null;
            }
        },
        startStreaming(streamUrl) {
            const component = this.$refs.videoPlayer;
            const playerElement = component?.$refs?.player;
            if (!playerElement) return;

            this.cleanupWebRTC();

            if (this.isLiveStream) {
                console.log("[Viewer] Initiating native WebRTC pipeline for device:", this.device.id);

                if (!window.webrtcSocket) {
                    window.webrtcSocket = new Socket("/socket", { params: { token: this.token } });
                    window.webrtcSocket.connect();
                }

                const socket = window.webrtcSocket;
                const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
                this._webrtcPc = pc;

                const activeStream = this.stream || "main_stream";
                const channel = socket.channel(`device:${this.device.id}`, { stream: activeStream });
                this._webrtcChannel = channel;

                channel.join()
                    .receive("ok", () => console.log(`[WebRTC] Viewer joined ${this.device.id} on ${activeStream}`))
                    .receive("error", reason => console.error(`[WebRTC] Viewer Error:`, reason));

                channel.on("offer", ({ data }) => {
                    pc.setRemoteDescription(JSON.parse(data));
                    pc.createAnswer().then(answer => {
                        pc.setLocalDescription(answer);
                        channel.push("answer", JSON.stringify(answer));
                    });
                });

                channel.on("ice_candidate", ({ data }) => pc.addIceCandidate(JSON.parse(data)));
                
                pc.onicecandidate = (event) => {
                    if (event.candidate) channel.push("ice_candidate", JSON.stringify(event.candidate));
                };

                pc.ontrack = (track) => {
                    playerElement.srcObject = track.streams[0];
                };

                pc.onconnectionstatechange = () => {
                    if (pc.connectionState === "disconnected" || pc.connectionState === "failed") {
                        console.error(`[WebRTC] Disconnected for ${this.device.id}`);
                    }
                };

                // Bypass HLS initialization since WebRTC is engaged
                return;
            }

            // HLS Video initialization (Fallback for Recording Playback)
            playerElement.srcObject = null;
            component?.initHls(streamUrl);

            if (playerElement) {
                playerElement._hls = isProxy(component.player)
                    ? toRaw(component.player)
                    : component.player;
                const hls = playerElement._hls;

                hls.on(Hls.Events.FRAG_LOADED, (event, data) => {
                    this.stats.bytes = data.stats.total;
                    const duration = data.frag.duration;
                    this.stats.bytes += data.stats.total;
                });

                hls.on(Hls.Events.LEVEL_LOADED, (event, data) => {
                    const level = hls.levels[data.level];
                    this.stats.bandwidth = convertBitrate(
                        hls.bandwidthEstimate,
                    );
                    this.stats.resolution = `${level.width}x${level.height}`;
                    this.stats.codec = level.videoCodec || level.codecs;
                    this.bitrate = convertBitrate(level.bitrate);
                    this.stats.availableLevels = hls.levels.length;
                    // this.stats.frameRate = level.frameRate;
                    this.stats.resolution = `${hls.levels[data.level].width}x${hls.levels[data.level].height}`;
                });

                // Playback State Events
                setInterval(() => {
                    const quality = playerElement.getVideoPlaybackQuality?.();
                    if (quality) {
                        this.stats.droppedFrames = quality.droppedVideoFrames;
                        this.stats.totalVideoFrames = quality.totalVideoFrames;
                        this.stats.corruptedVideoFrames =
                            quality.corruptedVideoFrames;
                    }
                }, 2000);
            }
        },
    },
});

function convertBitrate(bitRate) {
    const mbpsFactor = 1000 * 1000;
    const bitRateMbps = bitRate / mbpsFactor;

    return bitRateMbps < 1
        ? `${(bitRateMbps * 1000).toFixed(2)} Kbps`
        : `${bitRateMbps.toFixed(2)} Mbps`;
}
</script>

<style lang="scss">
.dashboard-viewer {
    display: flex !important;
    flex-direction: column !important;
    height: 100% !important;
    min-height: 0 !important;

    .top-bar {
        min-height: 2.5em;
        flex-shrink: 0;
    }

    // Force ELayout (second child) to expand and fill remaining space
    > :nth-child(2) {
        flex: 1 1 0% !important;
        min-height: 0 !important;
        overflow: hidden;
    }

    // Timeline wrapper (last child) stays at fixed height
    > :last-child {
        flex-shrink: 0;
    }

    .tooltip {
        z-index: 100;
    }

    .right-buttons .tooltip {
        transform: translate(-80%, 0) !important;
    }
}
</style>
