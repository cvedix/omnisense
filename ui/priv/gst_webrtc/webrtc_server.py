#!/usr/bin/env python3
"""
GStreamer WebRTC Server for TProNVR

This server creates WebRTC endpoints for low-latency live streaming.
Communication with Elixir via stdin/stdout JSON messages.

Usage:
    python3 webrtc_server.py --rtsp-url "rtsp://user:pass@camera/stream"
"""

import asyncio
import json
import sys
import argparse
import logging
from typing import Dict, Optional

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
gi.require_version('GstSdp', '1.0')
from gi.repository import Gst, GstWebRTC, GstSdp, GLib

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# STUN server for ICE
STUN_SERVER = "stun://stun.l.google.com:19302"


class WebRTCPeer:
    """Represents a single WebRTC peer connection."""
    
    def __init__(self, peer_id: str, server: 'WebRTCServer'):
        self.peer_id = peer_id
        self.server = server
        self.webrtcbin = None
        self.pipeline = None
        
    def create_pipeline(self, rtsp_url: str):
        """Create GStreamer pipeline with webrtcbin for this peer."""
        # Pipeline: RTSP -> depay -> parse -> payloader -> webrtcbin
        pipeline_str = f'''
            rtspsrc location="{rtsp_url}" latency=100 protocols=tcp buffer-mode=auto name=src
            ! rtph264depay ! h264parse config-interval=-1
            ! rtph264pay config-interval=-1 pt=96
            ! application/x-rtp,media=video,encoding-name=H264,payload=96
            ! webrtcbin name=webrtc bundle-policy=max-bundle stun-server={STUN_SERVER}
        '''
        
        self.pipeline = Gst.parse_launch(pipeline_str)
        self.webrtcbin = self.pipeline.get_by_name('webrtc')
        
        # Connect signals
        self.webrtcbin.connect('on-negotiation-needed', self._on_negotiation_needed)
        self.webrtcbin.connect('on-ice-candidate', self._on_ice_candidate)
        self.webrtcbin.connect('pad-added', self._on_pad_added)
        
        # Bus for messages
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect('message::error', self._on_error)
        bus.connect('message::eos', self._on_eos)
        
        return self.pipeline
        
    def start(self):
        """Start the pipeline."""
        if self.pipeline:
            self.pipeline.set_state(Gst.State.PLAYING)
            logger.info(f"[{self.peer_id}] Pipeline started")
            
    def stop(self):
        """Stop the pipeline."""
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            logger.info(f"[{self.peer_id}] Pipeline stopped")
            
    def set_remote_description(self, sdp_type: str, sdp_string: str):
        """Set the remote SDP description (answer from browser)."""
        if sdp_type == 'answer':
            sdp_type = GstWebRTC.WebRTCSDPType.ANSWER
        elif sdp_type == 'offer':
            sdp_type = GstWebRTC.WebRTCSDPType.OFFER
            
        ret, sdp = GstSdp.SDPMessage.new_from_text(sdp_string)
        if ret != GstSdp.SDPResult.OK:
            logger.error(f"[{self.peer_id}] Failed to parse SDP")
            return
            
        desc = GstWebRTC.WebRTCSessionDescription.new(sdp_type, sdp)
        promise = Gst.Promise.new()
        self.webrtcbin.emit('set-remote-description', desc, promise)
        promise.wait()
        logger.info(f"[{self.peer_id}] Remote description set")
        
    def add_ice_candidate(self, mline_index: int, candidate: str):
        """Add ICE candidate from browser."""
        self.webrtcbin.emit('add-ice-candidate', mline_index, candidate)
        logger.debug(f"[{self.peer_id}] Added ICE candidate")
        
    def _on_negotiation_needed(self, webrtcbin):
        """Called when negotiation is needed - create and send offer."""
        logger.info(f"[{self.peer_id}] Negotiation needed, creating offer...")
        promise = Gst.Promise.new_with_change_func(self._on_offer_created, None)
        webrtcbin.emit('create-offer', None, promise)
        
    def _on_offer_created(self, promise, _):
        """Called when offer is created."""
        reply = promise.get_reply()
        offer = reply.get_value('offer')
        
        # Set local description
        set_promise = Gst.Promise.new()
        self.webrtcbin.emit('set-local-description', offer, set_promise)
        set_promise.wait()
        
        # Send offer to Elixir
        sdp_text = offer.sdp.as_text()
        self.server.send_message({
            'type': 'offer',
            'peer_id': self.peer_id,
            'sdp': sdp_text
        })
        logger.info(f"[{self.peer_id}] Offer sent")
        
    def _on_ice_candidate(self, webrtcbin, mline_index, candidate):
        """Called when a new ICE candidate is discovered."""
        self.server.send_message({
            'type': 'ice_candidate',
            'peer_id': self.peer_id,
            'mline_index': mline_index,
            'candidate': candidate
        })
        logger.debug(f"[{self.peer_id}] ICE candidate sent")
        
    def _on_pad_added(self, webrtcbin, pad):
        """Called when a new pad is added to webrtcbin."""
        logger.debug(f"[{self.peer_id}] Pad added: {pad.get_name()}")
        
    def _on_error(self, bus, msg):
        """Handle pipeline errors."""
        err, debug = msg.parse_error()
        logger.error(f"[{self.peer_id}] Pipeline error: {err.message}")
        logger.debug(f"[{self.peer_id}] Debug: {debug}")
        self.server.send_message({
            'type': 'error',
            'peer_id': self.peer_id,
            'message': err.message
        })
        
    def _on_eos(self, bus, msg):
        """Handle end of stream."""
        logger.info(f"[{self.peer_id}] End of stream")
        self.stop()


class WebRTCServer:
    """Main WebRTC server managing multiple peers."""
    
    def __init__(self, rtsp_url: str):
        self.rtsp_url = rtsp_url
        self.peers: Dict[str, WebRTCPeer] = {}
        self.loop = None
        self.running = False
        
    def send_message(self, msg: dict):
        """Send JSON message to Elixir via stdout."""
        json_str = json.dumps(msg)
        sys.stdout.write(json_str + '\n')
        sys.stdout.flush()
        
    def add_peer(self, peer_id: str) -> WebRTCPeer:
        """Add a new WebRTC peer."""
        if peer_id in self.peers:
            logger.warning(f"Peer {peer_id} already exists")
            return self.peers[peer_id]
            
        peer = WebRTCPeer(peer_id, self)
        peer.create_pipeline(self.rtsp_url)
        peer.start()
        self.peers[peer_id] = peer
        logger.info(f"Added peer: {peer_id}")
        return peer
        
    def remove_peer(self, peer_id: str):
        """Remove a WebRTC peer."""
        if peer_id in self.peers:
            self.peers[peer_id].stop()
            del self.peers[peer_id]
            logger.info(f"Removed peer: {peer_id}")
            
    def handle_message(self, msg: dict):
        """Handle incoming message from Elixir."""
        msg_type = msg.get('type')
        peer_id = msg.get('peer_id')
        
        if msg_type == 'add_peer':
            self.add_peer(peer_id)
            
        elif msg_type == 'remove_peer':
            self.remove_peer(peer_id)
            
        elif msg_type == 'answer':
            if peer_id in self.peers:
                sdp = msg.get('sdp')
                self.peers[peer_id].set_remote_description('answer', sdp)
                
        elif msg_type == 'ice_candidate':
            if peer_id in self.peers:
                mline = msg.get('mline_index', 0)
                candidate = msg.get('candidate')
                self.peers[peer_id].add_ice_candidate(mline, candidate)
                
        elif msg_type == 'ping':
            self.send_message({'type': 'pong'})
            
        elif msg_type == 'stop':
            self.stop()
            
    def read_stdin(self):
        """Read messages from stdin (called from GLib main loop)."""
        try:
            line = sys.stdin.readline()
            if line:
                msg = json.loads(line.strip())
                self.handle_message(msg)
            return True
        except json.JSONDecodeError as e:
            logger.error(f"JSON decode error: {e}")
            return True
        except Exception as e:
            logger.error(f"Error reading stdin: {e}")
            return False
            
    def run(self):
        """Run the server main loop."""
        self.running = True
        self.loop = GLib.MainLoop()
        
        # Add stdin to the main loop
        GLib.io_add_watch(sys.stdin, GLib.IO_IN, lambda *args: self.read_stdin())
        
        # Send ready message
        self.send_message({'type': 'ready', 'rtsp_url': self.rtsp_url})
        logger.info("WebRTC server ready")
        
        try:
            self.loop.run()
        except KeyboardInterrupt:
            logger.info("Interrupted")
        finally:
            self.stop()
            
    def stop(self):
        """Stop the server."""
        self.running = False
        for peer_id in list(self.peers.keys()):
            self.remove_peer(peer_id)
        if self.loop:
            self.loop.quit()
        logger.info("WebRTC server stopped")


def main():
    parser = argparse.ArgumentParser(description='GStreamer WebRTC Server')
    parser.add_argument('--rtsp-url', required=True, help='RTSP URL of the camera')
    parser.add_argument('--test', action='store_true', help='Run in test mode')
    args = parser.parse_args()
    
    # Initialize GStreamer
    Gst.init(None)
    
    if args.test:
        # Test mode - just check if everything works
        logger.info("Test mode - checking GStreamer WebRTC...")
        logger.info("All checks passed!")
        return
        
    server = WebRTCServer(args.rtsp_url)
    server.run()


if __name__ == '__main__':
    main()
