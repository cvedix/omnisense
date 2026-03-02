/**
 * GStreamer WebRTC Client
 * 
 * Low-latency live streaming via WebRTC using GStreamer webrtcbin backend.
 * This connects to the gst_webrtc Phoenix channel for signaling.
 */

import { Socket } from "phoenix"

/**
 * GStreamer WebRTC Player
 * 
 * Usage:
 *   const player = new GstWebRTCPlayer(videoElement, deviceId, token);
 *   player.connect();
 */
export class GstWebRTCPlayer {
    constructor(videoElement, deviceId, token) {
        this.videoElement = videoElement
        this.deviceId = deviceId
        this.token = token
        this.socket = null
        this.channel = null
        this.pc = null
        this.connected = false
    }

    /**
     * Connect to WebRTC stream
     */
    connect() {
        // Create WebSocket connection
        this.socket = new Socket("/socket", { params: { token: this.token } })
        this.socket.connect()

        // Join the GStreamer WebRTC channel
        this.channel = this.socket.channel(`gst_webrtc:${this.deviceId}`, {})

        this.channel.join()
            .receive("ok", resp => {
                console.log("[GstWebRTC] Connected to channel")
                this._setupPeerConnection()
            })
            .receive("error", reason => {
                console.error("[GstWebRTC] Failed to join channel:", reason)
            })

        // Handle signaling messages from server
        this.channel.on("offer", (msg) => this._handleOffer(msg))
        this.channel.on("ice_candidate", (msg) => this._handleIceCandidate(msg))
        this.channel.on("error", (msg) => this._handleError(msg))
    }

    /**
     * Disconnect from WebRTC stream
     */
    disconnect() {
        if (this.pc) {
            this.pc.close()
            this.pc = null
        }
        if (this.channel) {
            this.channel.leave()
            this.channel = null
        }
        if (this.socket) {
            this.socket.disconnect()
            this.socket = null
        }
        this.connected = false
        console.log("[GstWebRTC] Disconnected")
    }

    _setupPeerConnection() {
        this.pc = new RTCPeerConnection({
            iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
        })

        // Handle incoming tracks
        this.pc.ontrack = (event) => {
            console.log("[GstWebRTC] Received track:", event.track.kind)
            if (event.streams && event.streams[0]) {
                this.videoElement.srcObject = event.streams[0]
            }
        }

        // Handle ICE candidates
        this.pc.onicecandidate = (event) => {
            if (event.candidate) {
                this.channel.push("ice_candidate", JSON.stringify({
                    candidate: event.candidate.candidate,
                    sdpMLineIndex: event.candidate.sdpMLineIndex,
                    sdpMid: event.candidate.sdpMid
                }))
            }
        }

        // Handle connection state changes
        this.pc.onconnectionstatechange = () => {
            console.log("[GstWebRTC] Connection state:", this.pc.connectionState)
            if (this.pc.connectionState === 'connected') {
                this.connected = true
            } else if (this.pc.connectionState === 'disconnected' ||
                this.pc.connectionState === 'failed') {
                this.connected = false
            }
        }

        this.pc.oniceconnectionstatechange = () => {
            console.log("[GstWebRTC] ICE state:", this.pc.iceConnectionState)
        }
    }

    async _handleOffer(msg) {
        try {
            const offer = JSON.parse(msg.data)
            console.log("[GstWebRTC] Received offer")

            await this.pc.setRemoteDescription(new RTCSessionDescription(offer))

            const answer = await this.pc.createAnswer()
            await this.pc.setLocalDescription(answer)

            this.channel.push("answer", JSON.stringify({
                type: answer.type,
                sdp: answer.sdp
            }))

            console.log("[GstWebRTC] Sent answer")
        } catch (error) {
            console.error("[GstWebRTC] Error handling offer:", error)
        }
    }

    _handleIceCandidate(msg) {
        try {
            const candidate = JSON.parse(msg.data)
            console.log("[GstWebRTC] Received ICE candidate")

            this.pc.addIceCandidate(new RTCIceCandidate({
                candidate: candidate.candidate,
                sdpMLineIndex: candidate.sdpMLineIndex || 0,
                sdpMid: candidate.sdpMid
            }))
        } catch (error) {
            console.error("[GstWebRTC] Error handling ICE candidate:", error)
        }
    }

    _handleError(msg) {
        console.error("[GstWebRTC] Server error:", msg.message)
    }
}

/**
 * Auto-initialize WebRTC players for elements with data-gst-webrtc attribute
 */
export function initGstWebRTC() {
    const players = document.querySelectorAll('[data-gst-webrtc]')

    players.forEach(element => {
        const deviceId = element.dataset.device
        const token = window.token || element.dataset.token

        if (deviceId && token) {
            const player = new GstWebRTCPlayer(element, deviceId, token)
            player.connect()

            // Store player instance for cleanup
            element._gstWebRTCPlayer = player
        }
    })
}

// Auto-init when DOM is ready
if (typeof window !== 'undefined') {
    window.addEventListener('load', () => {
        if (document.querySelector('[data-gst-webrtc]')) {
            initGstWebRTC()
        }
    })

    // Export for manual initialization
    window.GstWebRTCPlayer = GstWebRTCPlayer
    window.initGstWebRTC = initGstWebRTC
}
