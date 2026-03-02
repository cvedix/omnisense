// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { getHooks } from "live_vue"
import Hls from "hls.js"
import liveVueApp from "../vue"
import topbar from "topbar"
import "flowbite/dist/flowbite.phoenix"
import "../css/app.css"

const toolTipId = document.getElementById('tooltipContent');

let Hooks = {
    SwitchDarkMode: {
        mounted() {
            // Initialize theme from localStorage
            const savedTheme = localStorage.getItem('theme-mode');
            const lightSwitch = this.el;

            // Default is dark mode (no 'light' class)
            // When checked = light mode, unchecked = dark mode
            if (savedTheme === 'light') {
                document.documentElement.classList.add('light');
                lightSwitch.checked = true;
            } else {
                document.documentElement.classList.remove('light');
                lightSwitch.checked = false;
            }

            this.el.addEventListener("change", this.switchTheme);
        },
        switchTheme(event) {
            const lightSwitch = document.getElementById("light-switch");
            if (lightSwitch.checked) {
                // Switch to LIGHT mode
                document.documentElement.classList.add('light');
                localStorage.setItem('theme-mode', 'light');
            } else {
                // Switch to DARK mode (default)
                document.documentElement.classList.remove('light');
                localStorage.setItem('theme-mode', 'dark');
            }

            document.documentElement.dispatchEvent(
                new CustomEvent("theme-change")
            )
        }
    },
    HighlightSyntax: {
        highlight: async (el) => {
            const Shiki = await import("https://esm.sh/shiki@3.0.0")
            const code = el.innerText.trim()
            const lang = el.dataset.lang ?? "txt"
            const isDarkMode = [null, 'true'].includes(localStorage.getItem('dark-mode'))
            const theme = isDarkMode ? "github-dark-dimmed" : "github-light"

            el.innerHTML = await Shiki.codeToHtml(code, { lang, theme })
        },
        mounted() {
            this.highlight(this.el)
            document.documentElement.addEventListener("dark-mode-change", () => this.highlight(this.el))
        },
        updated() {
            this.highlight(this.el)
        }
    },

    FlowbiteInit: {
        mounted() {
            initFlowbite()

        },
        updated() {
            initFlowbite()

        }
    },
    HLSPlayer: {
        mounted() {
            this.initPlayer()
        },
        updated() {
            const video = this.el
            const deviceId = video.dataset.deviceId
            const loadingEl = document.getElementById(`loading-${deviceId}`)

            // If video is already playing, hide loading immediately
            if (!video.paused && video.readyState >= 2) {
                if (loadingEl) loadingEl.style.display = 'none'
            }

            // Re-init if device changed
            if (this.deviceId !== deviceId) {
                if (this.hls) this.hls.destroy()
                this.initPlayer()
            }
        },
        initPlayer() {
            const video = this.el
            const deviceId = video.dataset.deviceId
            this.deviceId = deviceId

            // Use explicit data-src if provided, otherwise construct ZLMediaKit URL
            const dataSrc = video.dataset.src
            const zlmHost = window.location.hostname
            const zlmPort = 8080
            const src = dataSrc || `http://${zlmHost}:${zlmPort}/live/${deviceId}/hls.m3u8`

            const loadingEl = document.getElementById(`loading-${deviceId}`)

            const hideLoading = () => {
                if (loadingEl) loadingEl.style.display = 'none'
            }

            // Hide loading immediately if video already has data or is playing
            if (video.readyState >= 2 || !video.paused) {
                hideLoading()
            }

            // Always add playing event listener
            video.addEventListener('playing', hideLoading)
            video.addEventListener('loadeddata', hideLoading, { once: true })

            console.log('[HLS] Initializing ZLMediaKit HLS for device:', deviceId)
            console.log('[HLS] Source:', src)

            if (Hls.isSupported()) {
                const hls = new Hls({
                    manifestLoadingTimeOut: 30000,
                    manifestLoadingMaxRetry: 3,
                    levelLoadingTimeOut: 30000,
                    enableWorker: true,
                    lowLatencyMode: true,
                })

                hls.loadSource(src)
                hls.attachMedia(video)

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    console.log('[HLS] Manifest parsed, starting playback')
                    hideLoading()
                    video.play().catch(() => { })
                })

                hls.on(Hls.Events.ERROR, (event, data) => {
                    console.log('[HLS] Error:', data.type, data.details)
                    if (data.fatal) {
                        if (loadingEl) {
                            loadingEl.innerHTML = '<div class="text-center text-white"><p class="text-sm">Stream unavailable</p></div>'
                        }
                    }
                })

                this.hls = hls
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                // Safari native HLS
                video.src = src
                video.addEventListener('loadedmetadata', () => {
                    hideLoading()
                    video.play()
                })
            }
        },
        destroyed() {
            if (this.hls) {
                this.hls.destroy()
            }
        }
    },
    HeatmapCanvas: {
        mounted() {
            this.canvas = document.getElementById('heatmap-canvas')
            this.ctx = this.canvas.getContext('2d')
            this.gridSize = parseInt(this.el.dataset.gridSize) || 50
            this.heatmapData = JSON.parse(this.el.dataset.heatmap || '[]')

            this.resizeCanvas()
            this.render()

            window.addEventListener('resize', () => this.resizeCanvas())
        },

        updated() {
            this.heatmapData = JSON.parse(this.el.dataset.heatmap || '[]')
            this.render()
        },

        resizeCanvas() {
            const container = this.el
            const rect = container.getBoundingClientRect()
            this.canvas.width = rect.width
            this.canvas.height = rect.height
            this.render()
        },

        render() {
            if (!this.ctx) return

            const ctx = this.ctx
            const width = this.canvas.width
            const height = this.canvas.height
            const gridSize = this.gridSize
            const cellWidth = width / gridSize
            const cellHeight = height / gridSize

            // Clear canvas (transparent - allows video to show through)
            ctx.clearRect(0, 0, width, height)

            if (!this.heatmapData || this.heatmapData.length === 0) {
                return
            }

            // Find max value for normalization
            let maxVal = 0
            for (let row of this.heatmapData) {
                for (let val of row) {
                    if (val > maxVal) maxVal = val
                }
            }

            if (maxVal === 0) return

            // Draw heatmap cells (semi-transparent overlay)
            for (let row = 0; row < this.heatmapData.length; row++) {
                for (let col = 0; col < this.heatmapData[row].length; col++) {
                    const value = this.heatmapData[row][col]
                    if (value === 0) continue

                    const intensity = value / maxVal
                    const color = this.getHeatColor(intensity)

                    ctx.fillStyle = color
                    ctx.fillRect(
                        col * cellWidth,
                        row * cellHeight,
                        cellWidth + 1, // +1 to avoid gaps
                        cellHeight + 1
                    )
                }
            }

            // Add subtle grid overlay (optional, for visibility)
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)'
            ctx.lineWidth = 0.5
            for (let i = 0; i <= gridSize; i++) {
                // Vertical lines
                ctx.beginPath()
                ctx.moveTo(i * cellWidth, 0)
                ctx.lineTo(i * cellWidth, height)
                ctx.stroke()
                // Horizontal lines
                ctx.beginPath()
                ctx.moveTo(0, i * cellHeight)
                ctx.lineTo(width, i * cellHeight)
                ctx.stroke()
            }
        },

        drawBackground() {
            // Clear canvas (transparent) instead of dark background
            // This allows video player underneath to be visible
            this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
        },

        getHeatColor(intensity) {
            // Color gradient: transparent blue -> green -> yellow -> red
            // intensity is 0-1
            let r, g, b, a

            if (intensity < 0.25) {
                // Blue to cyan
                const t = intensity / 0.25
                r = 0
                g = Math.floor(255 * t)
                b = 255
                a = 0.3 + intensity * 0.7
            } else if (intensity < 0.5) {
                // Cyan to green
                const t = (intensity - 0.25) / 0.25
                r = 0
                g = 255
                b = Math.floor(255 * (1 - t))
                a = 0.5 + intensity * 0.5
            } else if (intensity < 0.75) {
                // Green to yellow
                const t = (intensity - 0.5) / 0.25
                r = Math.floor(255 * t)
                g = 255
                b = 0
                a = 0.6 + intensity * 0.4
            } else {
                // Yellow to red
                const t = (intensity - 0.75) / 0.25
                r = 255
                g = Math.floor(255 * (1 - t))
                b = 0
                a = 0.7 + intensity * 0.3
            }

            return `rgba(${r}, ${g}, ${b}, ${a})`
        }
    },
    BarChart: {
        mounted() {
            this.chartData = JSON.parse(this.el.dataset.chart || '[]')
            this.groupBy = this.el.dataset.groupBy || 'hour'
            this.colorMode = this.el.dataset.colorMode || 'multi'
            this.renderChart()

            this.handleEvent("chart_update", ({ data, group_by }) => {
                this.chartData = data
                this.groupBy = group_by
                this.renderChart()
            })

            this._resizeHandler = () => this.renderChart()
            window.addEventListener('resize', this._resizeHandler)
        },

        destroyed() {
            window.removeEventListener('resize', this._resizeHandler)
            if (this._tooltip && this._tooltip.parentNode) {
                this._tooltip.parentNode.removeChild(this._tooltip)
            }
        },

        renderChart() {
            const container = this.el
            container.innerHTML = ''

            const data = this.chartData
            if (!data || data.length === 0) {
                container.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:rgba(255,255,255,0.4);font-size:14px;">No data found for this period</div>'
                return
            }

            const maxCount = Math.max(...data.map(d => d.count), 1)
            const barAreaHeight = 220
            const yAxisW = 40
            const barGap = data.length > 30 ? 1 : data.length > 15 ? 2 : 4

            // Colors
            const colors = [
                ['#4ade80', '#16a34a'], ['#60a5fa', '#2563eb'], ['#f472b6', '#db2777'],
                ['#facc15', '#ca8a04'], ['#a78bfa', '#7c3aed'], ['#fb923c', '#ea580c'],
                ['#34d399', '#059669'], ['#f87171', '#dc2626'], ['#38bdf8', '#0284c7'],
                ['#c084fc', '#9333ea']
            ]

            // Cleanup old tooltip
            if (this._tooltip && this._tooltip.parentNode) {
                this._tooltip.parentNode.removeChild(this._tooltip)
            }
            const tooltip = document.createElement('div')
            tooltip.style.cssText = 'position:fixed;background:#111;border:1px solid #22c55e;color:#fff;padding:8px 14px;border-radius:6px;font-size:12px;pointer-events:none;display:none;z-index:9999;box-shadow:0 4px 16px rgba(0,0,0,0.6);'
            document.body.appendChild(tooltip)
            this._tooltip = tooltip

            // Main wrapper
            const w = document.createElement('div')
            w.style.cssText = 'display:flex;flex-direction:column;gap:0;'

            // --- Chart row (Y-axis + bars) ---
            const chartRow = document.createElement('div')
            chartRow.style.cssText = `display:flex;height:${barAreaHeight}px;`

            // Y-axis column
            const yCol = document.createElement('div')
            yCol.style.cssText = `width:${yAxisW}px;flex-shrink:0;position:relative;`
            for (let i = 0; i <= 4; i++) {
                const val = Math.round((maxCount / 4) * (4 - i))
                const t = document.createElement('div')
                t.style.cssText = `position:absolute;right:4px;top:${(i / 4) * 100}%;transform:translateY(-50%);font-size:10px;color:rgba(255,255,255,0.5);font-family:monospace;`
                t.textContent = val
                yCol.appendChild(t)
            }
            chartRow.appendChild(yCol)

            // Bars column
            const barsCol = document.createElement('div')
            barsCol.style.cssText = `flex:1;display:flex;align-items:flex-end;gap:${barGap}px;border-left:1px solid rgba(34,197,94,0.3);border-bottom:1px solid rgba(34,197,94,0.3);position:relative;padding:0 4px;`

            // Gridlines
            for (let i = 1; i <= 3; i++) {
                const gl = document.createElement('div')
                gl.style.cssText = `position:absolute;left:0;right:0;bottom:${(i / 4) * 100}%;height:1px;background:rgba(34,197,94,0.08);pointer-events:none;`
                barsCol.appendChild(gl)
            }

            data.forEach((d, i) => {
                const [cL, cD] = this.colorMode === 'single' ? colors[0] : colors[i % colors.length]
                const hPct = (d.count / maxCount) * 100

                const bc = document.createElement('div')
                bc.style.cssText = `flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;min-width:3px;max-width:80px;cursor:pointer;`

                // Count above bar
                if (d.count > 0 && data.length <= 15) {
                    const cl = document.createElement('div')
                    cl.style.cssText = `font-size:10px;font-weight:700;color:${cL};margin-bottom:1px;font-family:monospace;`
                    cl.textContent = d.count
                    bc.appendChild(cl)
                }

                const bar = document.createElement('div')
                bar.style.cssText = `width:${data.length > 20 ? '100' : '65'}%;background:linear-gradient(180deg,${cL},${cD});border-radius:3px 3px 0 0;height:${hPct}%;min-height:${d.count > 0 ? '3' : '0'}px;transition:all 0.2s;`

                bc.addEventListener('mouseover', () => {
                    bar.style.filter = 'brightness(1.3)'
                    bar.style.boxShadow = `0 0 10px ${cL}50`
                    tooltip.style.display = 'block'
                    tooltip.innerHTML = `<div style="color:${cL};font-weight:600;margin-bottom:2px">${d.label}</div><div style="font-size:18px;font-weight:bold">${d.count}</div>`
                })
                bc.addEventListener('mousemove', (e) => {
                    tooltip.style.left = (e.clientX + 12) + 'px'
                    tooltip.style.top = (e.clientY - 55) + 'px'
                })
                bc.addEventListener('mouseout', () => {
                    bar.style.filter = 'none'
                    bar.style.boxShadow = 'none'
                    tooltip.style.display = 'none'
                })

                bc.appendChild(bar)
                barsCol.appendChild(bc)
            })

            chartRow.appendChild(barsCol)
            w.appendChild(chartRow)

            // --- X-axis labels row ---
            const xRow = document.createElement('div')
            xRow.style.cssText = `display:flex;padding-left:${yAxisW}px;gap:${barGap}px;padding-top:6px;height:60px;`

            const showEvery = Math.max(1, Math.ceil(data.length / 20))
            data.forEach((d, i) => {
                const ld = document.createElement('div')
                ld.style.cssText = 'flex:1;min-width:3px;max-width:80px;overflow:visible;text-align:center;position:relative;'

                if (i % showEvery === 0) {
                    let lt = d.label
                    if (this.groupBy === 'hour') {
                        const p = lt.split(' ')
                        lt = p.length === 2 ? p[1] : lt
                    } else if (this.groupBy === 'day') {
                        lt = lt.slice(5)
                    }
                    const s = document.createElement('span')
                    s.style.cssText = 'color:rgba(255,255,255,0.6);font-size:10px;font-family:monospace;white-space:nowrap;position:absolute;left:50%;top:0;transform:rotate(-40deg);transform-origin:left top;'
                    s.textContent = lt
                    ld.appendChild(s)
                }
                xRow.appendChild(ld)
            })

            w.appendChild(xRow)
            container.appendChild(w)
        }
    },
    EventToast: {
        mounted() {
            this.toastId = 0
            this.notifLog = []
            this.unreadCount = 0
            this.handleEvent("ai_event_toast", (data) => this.showToast(data))

            // Close panel on outside click
            document.addEventListener('click', (e) => {
                const panel = document.getElementById('notification-log-panel')
                const bell = document.getElementById('notification-bell-btn')
                if (panel && bell && !panel.contains(e.target) && !bell.contains(e.target)) {
                    panel.classList.add('hidden')
                }
            })

            // Clear all handler
            window._clearNotificationLog = () => {
                this.notifLog = []
                this.unreadCount = 0
                this.updateBadge()
                this.renderLogPanel()
            }
        },

        showToast(data) {
            const id = ++this.toastId
            const container = this.el

            const typeConfig = {
                'event-loitering': { label: 'LOITERING START', color: '#facc15', border: '#a16207', icon: '⏳' },
                'event-loitering-end': { label: 'LOITERING END', color: '#9ca3af', border: '#6b7280', icon: '✅' },
                'event-line-crossing': { label: 'LINE CROSSING', color: '#60a5fa', border: '#2563eb', icon: '🚶' },
                'event-intrusion': { label: 'INTRUSION', color: '#f87171', border: '#dc2626', icon: '🚨' },
                'event-intrusion-end': { label: 'INTRUSION END', color: '#9ca3af', border: '#6b7280', icon: '✅' },
                'event-area-enter': { label: 'AREA ENTER', color: '#4ade80', border: '#16a34a', icon: '📥' },
                'event-area-exit': { label: 'AREA EXIT', color: '#fb923c', border: '#ea580c', icon: '📤' },
            }
            const cfg = typeConfig[data.event_type] || { label: data.event_type, color: '#4ade80', border: '#16a34a', icon: '📡' }

            // Store in notification log
            this.notifLog.unshift({ ...data, cfg, timestamp: new Date() })
            if (this.notifLog.length > 50) this.notifLog.pop()
            this.unreadCount++
            this.updateBadge()
            this.renderLogPanel()

            const toast = document.createElement('div')
            toast.id = `toast-${id}`
            toast.style.cssText = 'pointer-events:auto;animation:toastSlideIn 0.35s ease-out;cursor:pointer;'

            toast.innerHTML = `
                <div style="background:rgba(10,10,10,0.95);backdrop-filter:blur(10px);border:1px solid ${cfg.border}80;border-radius:10px;padding:12px;box-shadow:0 8px 32px rgba(0,0,0,0.7);transition:transform 0.2s;">
                    <div style="display:flex;gap:10px;">
                        ${data.thumbnail
                    ? `<img src="${data.thumbnail}" style="width:52px;height:52px;border-radius:6px;object-fit:cover;border:1px solid ${cfg.border}40;flex-shrink:0;" />`
                    : `<div style="width:52px;height:52px;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:22px;background:${cfg.border}30;flex-shrink:0;">${cfg.icon}</div>`
                }
                        <div style="flex:1;min-width:0;">
                            <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;">
                                <span style="font-size:10px;font-weight:700;letter-spacing:0.5px;color:${cfg.color};">${cfg.label}</span>
                                <span style="font-size:10px;color:rgba(255,255,255,0.35);">${data.time_str}</span>
                            </div>
                            <div style="font-size:13px;color:white;font-weight:600;margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${data.area_name}</div>
                            <div style="display:flex;align-items:center;gap:8px;margin-top:4px;">
                                <span style="font-size:10px;color:rgba(255,255,255,0.45);">📷 ${data.device_name}</span>
                                ${data.object_class ? `<span style="font-size:10px;color:${cfg.color}80;">🏷 ${data.object_class}</span>` : ''}
                                ${data.duration ? `<span style="font-size:10px;color:#fb923c;">⏱ ${data.duration}</span>` : ''}
                            </div>
                        </div>
                        <div style="color:rgba(255,255,255,0.25);font-size:14px;cursor:pointer;align-self:flex-start;padding:0 2px;" class="toast-close">✕</div>
                    </div>
                    <div style="margin-top:8px;height:2px;background:rgba(255,255,255,0.08);border-radius:2px;overflow:hidden;">
                        <div style="height:100%;background:${cfg.color};border-radius:2px;animation:toastShrink 60s linear forwards;"></div>
                    </div>
                </div>
            `

            // Hover effect
            const card = toast.querySelector('div')
            toast.addEventListener('mouseenter', () => { card.style.transform = 'scale(1.02)' })
            toast.addEventListener('mouseleave', () => { card.style.transform = 'scale(1)' })

            // Click to navigate
            toast.addEventListener('click', (e) => {
                if (e.target.classList.contains('toast-close')) {
                    toast.style.animation = 'toastSlideOut 0.3s ease-in forwards'
                    setTimeout(() => toast.remove(), 300)
                    return
                }
                window.location.href = '/events/ai-events'
            })

            container.prepend(toast)

            // Keep max 5 toasts
            while (container.children.length > 5) {
                container.lastChild.remove()
            }

            // Auto dismiss after 60s
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.style.animation = 'toastSlideOut 0.3s ease-in forwards'
                    setTimeout(() => toast.remove(), 300)
                }
            }, 60000)
        },

        updateBadge() {
            const badge = document.getElementById('notification-badge')
            if (badge) {
                if (this.unreadCount > 0) {
                    badge.classList.remove('hidden')
                    badge.textContent = this.unreadCount > 99 ? '99+' : this.unreadCount
                } else {
                    badge.classList.add('hidden')
                }
            }
        },

        renderLogPanel() {
            const list = document.getElementById('notification-log-list')
            const empty = document.getElementById('notification-log-empty')
            if (!list) return

            if (this.notifLog.length === 0) {
                list.innerHTML = '<div class="px-4 py-6 text-center text-white/30 text-sm">No notifications yet</div>'
                return
            }

            list.innerHTML = this.notifLog.map(n => `
                <a href="/events/ai-events" class="block px-3 py-2 border-b border-green-900/30 hover:bg-green-900/20 transition-colors" style="text-decoration:none;">
                    <div style="display:flex;gap:8px;align-items:center;">
                        ${n.thumbnail
                    ? `<img src="${n.thumbnail}" style="width:36px;height:36px;border-radius:4px;object-fit:cover;flex-shrink:0;" />`
                    : `<div style="width:36px;height:36px;border-radius:4px;display:flex;align-items:center;justify-content:center;font-size:16px;background:${n.cfg.border}30;flex-shrink:0;">${n.cfg.icon}</div>`
                }
                        <div style="flex:1;min-width:0;">
                            <div style="display:flex;align-items:center;justify-content:space-between;">
                                <span style="font-size:10px;font-weight:700;color:${n.cfg.color};letter-spacing:0.3px;">${n.cfg.label}</span>
                                <span style="font-size:9px;color:rgba(255,255,255,0.3);">${n.time_str}</span>
                            </div>
                            <div style="font-size:12px;color:white;font-weight:500;margin-top:1px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${n.area_name}</div>
                            <div style="display:flex;gap:6px;margin-top:2px;">
                                <span style="font-size:9px;color:rgba(255,255,255,0.4);">📷 ${n.device_name}</span>
                                ${n.object_class ? `<span style="font-size:9px;color:${n.cfg.color}80;">🏷 ${n.object_class}</span>` : ''}
                                ${n.duration ? `<span style="font-size:9px;color:#fb923c;">⏱ ${n.duration}</span>` : ''}
                            </div>
                        </div>
                    </div>
                </a>
            `).join('')
        }
    },
    PieChart: {
        mounted() {
            this.chartData = JSON.parse(this.el.dataset.chart || '[]')
            this.renderChart()

            this.handleEvent("pie_chart_update", ({ data }) => {
                this.chartData = data
                this.renderChart()
            })

            this._resizeHandler = () => this.renderChart()
            window.addEventListener('resize', this._resizeHandler)
        },

        destroyed() {
            window.removeEventListener('resize', this._resizeHandler)
            if (this._tooltip && this._tooltip.parentNode) {
                this._tooltip.parentNode.removeChild(this._tooltip)
            }
        },

        renderChart() {
            const container = this.el
            container.innerHTML = ''

            const data = this.chartData
            if (!data || data.length === 0) {
                container.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:rgba(255,255,255,0.4);font-size:14px;">No data</div>'
                return
            }

            const total = data.reduce((s, d) => s + d.count, 0)
            if (total === 0) {
                container.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:rgba(255,255,255,0.4);font-size:14px;">No data</div>'
                return
            }

            const colors = ['#4ade80', '#60a5fa', '#f472b6', '#facc15', '#a78bfa', '#fb923c', '#34d399', '#f87171', '#38bdf8', '#c084fc']

            // Cleanup tooltip
            if (this._tooltip && this._tooltip.parentNode) {
                this._tooltip.parentNode.removeChild(this._tooltip)
            }
            const tooltip = document.createElement('div')
            tooltip.style.cssText = 'position:fixed;background:#111;border:1px solid #22c55e;color:#fff;padding:8px 14px;border-radius:6px;font-size:12px;pointer-events:none;display:none;z-index:9999;box-shadow:0 4px 16px rgba(0,0,0,0.6);'
            document.body.appendChild(tooltip)
            this._tooltip = tooltip

            const w = document.createElement('div')
            w.style.cssText = 'display:flex;align-items:center;justify-content:center;height:100%;gap:24px;'

            // SVG pie
            const size = Math.min(container.clientHeight || 200, 200)
            const cx = size / 2, cy = size / 2, r = size * 0.38, ir = size * 0.22

            const svgNS = 'http://www.w3.org/2000/svg'
            const svg = document.createElementNS(svgNS, 'svg')
            svg.setAttribute('width', size)
            svg.setAttribute('height', size)
            svg.setAttribute('viewBox', `0 0 ${size} ${size}`)
            svg.style.cssText = 'flex-shrink:0;'

            let startAngle = -Math.PI / 2
            data.forEach((d, i) => {
                const pct = d.count / total
                const angle = pct * 2 * Math.PI
                const endAngle = startAngle + angle
                const color = colors[i % colors.length]

                let el
                if (pct >= 0.999) {
                    // Full circle — use two concentric circle elements
                    const outer = document.createElementNS(svgNS, 'circle')
                    outer.setAttribute('cx', cx)
                    outer.setAttribute('cy', cy)
                    outer.setAttribute('r', r)
                    outer.setAttribute('fill', color)
                    svg.appendChild(outer)
                    const inner = document.createElementNS(svgNS, 'circle')
                    inner.setAttribute('cx', cx)
                    inner.setAttribute('cy', cy)
                    inner.setAttribute('r', ir)
                    inner.setAttribute('fill', '#0a0a0a')
                    svg.appendChild(inner)
                    // Use outer circle for hover
                    el = outer
                } else {
                    const largeArc = angle > Math.PI ? 1 : 0
                    const x1o = cx + r * Math.cos(startAngle)
                    const y1o = cy + r * Math.sin(startAngle)
                    const x2o = cx + r * Math.cos(endAngle)
                    const y2o = cy + r * Math.sin(endAngle)
                    const x1i = cx + ir * Math.cos(endAngle)
                    const y1i = cy + ir * Math.sin(endAngle)
                    const x2i = cx + ir * Math.cos(startAngle)
                    const y2i = cy + ir * Math.sin(startAngle)

                    const path = document.createElementNS(svgNS, 'path')
                    path.setAttribute('d', [
                        `M ${x1o} ${y1o}`,
                        `A ${r} ${r} 0 ${largeArc} 1 ${x2o} ${y2o}`,
                        `L ${x1i} ${y1i}`,
                        `A ${ir} ${ir} 0 ${largeArc} 0 ${x2i} ${y2i}`,
                        'Z'
                    ].join(' '))
                    path.setAttribute('fill', color)
                    svg.appendChild(path)
                    el = path
                }

                el.style.cssText = 'transition:all 0.2s;cursor:pointer;'
                el.addEventListener('mouseover', () => {
                    el.style.filter = 'brightness(1.3)'
                    tooltip.style.display = 'block'
                    tooltip.innerHTML = `<div style="color:${color};font-weight:600">${d.label}</div><div style="font-size:16px;font-weight:bold">${d.count} <span style="font-size:12px;color:rgba(255,255,255,0.5)">(${(pct * 100).toFixed(1)}%)</span></div>`
                })
                el.addEventListener('mousemove', (e) => {
                    tooltip.style.left = (e.clientX + 12) + 'px'
                    tooltip.style.top = (e.clientY - 50) + 'px'
                })
                el.addEventListener('mouseout', () => {
                    el.style.filter = 'none'
                    el.style.transform = 'none'
                    tooltip.style.display = 'none'
                })


                startAngle = endAngle
            })

            // Center text
            const centerText = document.createElementNS(svgNS, 'text')
            centerText.setAttribute('x', cx)
            centerText.setAttribute('y', cy - 6)
            centerText.setAttribute('text-anchor', 'middle')
            centerText.setAttribute('fill', 'white')
            centerText.setAttribute('font-size', '20')
            centerText.setAttribute('font-weight', 'bold')
            centerText.textContent = total

            const centerLabel = document.createElementNS(svgNS, 'text')
            centerLabel.setAttribute('x', cx)
            centerLabel.setAttribute('y', cy + 14)
            centerLabel.setAttribute('text-anchor', 'middle')
            centerLabel.setAttribute('fill', 'rgba(255,255,255,0.5)')
            centerLabel.setAttribute('font-size', '10')
            centerLabel.textContent = 'Total'

            svg.appendChild(centerText)
            svg.appendChild(centerLabel)
            w.appendChild(svg)

            // Legend
            const legend = document.createElement('div')
            legend.style.cssText = 'display:flex;flex-direction:column;gap:6px;'
            data.forEach((d, i) => {
                const row = document.createElement('div')
                row.style.cssText = 'display:flex;align-items:center;gap:8px;'

                const dot = document.createElement('div')
                dot.style.cssText = `width:10px;height:10px;border-radius:50%;background:${colors[i % colors.length]};flex-shrink:0;`

                const label = document.createElement('div')
                label.style.cssText = 'color:rgba(255,255,255,0.8);font-size:12px;'
                const pct = ((d.count / total) * 100).toFixed(1)
                label.innerHTML = `<span style="color:white;font-weight:600">${d.label}</span> <span style="color:rgba(255,255,255,0.4)">${d.count} (${pct}%)</span>`

                row.appendChild(dot)
                row.appendChild(label)
                legend.appendChild(row)
            })
            w.appendChild(legend)

            container.appendChild(w)
        }
    },
    CVEDIXFrame: {
        mounted() {
            this.instanceId = this.el.dataset.instanceId
            this.polling = true
            this.pollInterval = 100 // 10 FPS

            this.poll()
        },

        poll() {
            if (!this.polling) return

            const timestamp = Date.now()
            const newSrc = `/api/cvedix/instance/${this.instanceId}/frame?t=${timestamp}`

            // Create a new image to preload
            const img = new Image()
            img.onload = () => {
                if (this.polling && this.el) {
                    this.el.src = newSrc
                    setTimeout(() => this.poll(), this.pollInterval)
                }
            }
            img.onerror = () => {
                // On error, retry after a longer delay
                if (this.polling) {
                    setTimeout(() => this.poll(), 500)
                }
            }
            img.src = newSrc
        },

        destroyed() {
            this.polling = false
        }
    },
    AnalyticsDrawing: {
        mounted() {
            this.canvas = this.el
            this.ctx = this.canvas.getContext('2d')
            this.points = []
            this.existingShapes = []
            this.drawingMode = null // 'zone' or 'line'
            this.isDrawing = false

            // Edit mode state
            this.editMode = false
            this.editingShape = null  // {type, index, shapeIndex} - which shape and which point is being edited
            this.draggingPoint = null // Index of point being dragged
            this.isDragging = false

            // Get video element dimensions
            this.videoEl = document.getElementById(this.el.dataset.videoId)
            this.resizeCanvas()

            // Event listeners
            this.canvas.addEventListener('click', this.handleClick.bind(this))
            this.canvas.addEventListener('dblclick', this.handleDoubleClick.bind(this))
            this.canvas.addEventListener('mousemove', this.handleMouseMove.bind(this))
            this.canvas.addEventListener('mousedown', this.handleMouseDown.bind(this))
            this.canvas.addEventListener('mouseup', this.handleMouseUp.bind(this))
            this.canvas.addEventListener('mouseleave', this.handleMouseUp.bind(this))
            window.addEventListener('resize', this.resizeCanvas.bind(this))

            // Re-resize canvas when video dimensions become available
            if (this.videoEl) {
                this.videoEl.addEventListener('loadedmetadata', () => {
                    console.log('[AnalyticsDrawing] Video metadata loaded, resizing canvas', {
                        videoWidth: this.videoEl.videoWidth,
                        videoHeight: this.videoEl.videoHeight
                    })
                    this.resizeCanvas()
                })
                this.videoEl.addEventListener('loadeddata', () => {
                    console.log('[AnalyticsDrawing] Video data loaded, resizing canvas')
                    this.resizeCanvas()
                })
            }

            // Handle events from LiveView
            this.handleEvent("start_drawing", ({ mode }) => {
                this.startDrawing(mode)
            })

            this.handleEvent("cancel_drawing", () => {
                this.cancelDrawing()
            })

            this.handleEvent("load_shapes", ({ zones, lines }) => {
                console.log('[load_shapes] Received zones:', zones?.length || 0, 'lines:', lines?.length || 0)

                // Clear existing shapes
                this.existingShapes = []

                // Process zones from API - each zone has coordinates array with {x, y} objects
                if (zones && Array.isArray(zones)) {
                    zones.forEach(zone => {
                        const coords = this.parseCoordinates(zone.coordinates)
                        if (coords.length >= 3) {
                            this.existingShapes.push({
                                type: 'zone',
                                name: zone.name,
                                coordinates: coords,
                                color: this.parseColor(zone.color)
                            })
                            console.log(`[load_shapes] Added zone "${zone.name}" with ${coords.length} points`)
                        }
                    })
                }

                // Process lines from API
                if (lines && Array.isArray(lines)) {
                    lines.forEach(line => {
                        const coords = this.parseCoordinates(line.coordinates)
                        if (coords.length >= 2) {
                            this.existingShapes.push({
                                type: 'line',
                                name: line.name,
                                coordinates: coords,
                                color: this.parseColor(line.color),
                                direction: line.direction || 'Both'  // Store direction for arrows
                            })
                            console.log(`[load_shapes] Added line "${line.name}" with direction: ${line.direction}`)
                        }
                    })
                }

                console.log('[load_shapes] Total shapes:', this.existingShapes.length)

                // Draw immediately
                this.waitAndDraw()
            })

            // Helper: Parse coordinates from various formats
            this.parseCoordinates = (coords) => {
                if (!coords || !Array.isArray(coords)) return []
                return coords.map(c => ({
                    x: parseFloat(c.x ?? c['x'] ?? 0),
                    y: parseFloat(c.y ?? c['y'] ?? 0)
                })).filter(c => !isNaN(c.x) && !isNaN(c.y))
            }

            // Helper: Parse color from API format [r,g,b,a] (0-1 range) to [r,g,b,a] (0-255 range)
            this.parseColor = (color) => {
                if (!color || !Array.isArray(color) || color.length < 4) {
                    return [255, 165, 0, 200] // Default orange
                }
                const [r, g, b, a] = color
                // If values are in 0-1 range, convert to 0-255
                if (r <= 1 && g <= 1 && b <= 1) {
                    return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255), Math.round(a * 255)]
                }
                return [r, g, b, a]
            }

            // Helper: Wait for video ready then draw
            this.waitAndDraw = () => {
                const tryDraw = () => {
                    if (this.videoEl && this.videoEl.videoWidth > 0) {
                        this.resizeCanvas()
                        this.redraw()
                    } else {
                        setTimeout(tryDraw, 100)
                    }
                }
                tryDraw()
            }

            this.handleEvent("clear_shapes", () => {
                this.existingShapes = []
                this.editMode = false
                this.editingShape = null
                this.redraw()
            })

            // Handle finish_drawing from server (when user clicks Finish button)
            this.handleEvent("finish_drawing", () => {
                console.log('[AnalyticsDrawing] finish_drawing event from server, triggering finishDrawing()')
                this.finishDrawing()
            })

            // Handle clear_pending when user saves or cancels the zone configuration
            this.handleEvent("clear_pending", () => {
                console.log('[AnalyticsDrawing] clear_pending event - removing pending shape')
                this.pendingShape = null
                this.redraw()
            })

            // === EDIT MODE HANDLERS ===

            // Start edit mode for a shape
            this.handleEvent("start_edit", ({ shapeIndex }) => {
                console.log('[AnalyticsDrawing] start_edit mode for shape index:', shapeIndex)
                if (this.existingShapes[shapeIndex]) {
                    this.editMode = true
                    this.editingShape = { shapeIndex }
                    this.canvas.style.cursor = 'move'
                    this.redraw()
                }
            })

            // Cancel edit mode
            this.handleEvent("cancel_edit", () => {
                console.log('[AnalyticsDrawing] cancel_edit - exiting edit mode')
                this.editMode = false
                this.editingShape = null
                this.draggingPoint = null
                this.canvas.style.cursor = 'default'
                this.redraw()
            })

            // Save edited coordinates
            this.saveEdit = () => {
                console.log('[AnalyticsDrawing] saveEdit called, editMode:', this.editMode, 'editingShape:', this.editingShape)
                console.log('[AnalyticsDrawing] existingShapes:', this.existingShapes)

                // Try to get the shape from editingShape or use first existingShape
                let shape = null
                if (this.editingShape && this.existingShapes[this.editingShape.shapeIndex]) {
                    shape = this.existingShapes[this.editingShape.shapeIndex]
                } else if (this.existingShapes.length > 0) {
                    // Fallback: use first shape
                    shape = this.existingShapes[0]
                }

                if (!shape) {
                    console.error('[AnalyticsDrawing] No shape to save!')
                    return
                }

                console.log('[AnalyticsDrawing] Saving shape:', shape.name, 'coords:', shape.coordinates)

                const payload = {
                    type: shape.type,
                    name: shape.name,
                    coordinates: shape.coordinates
                }
                console.log('[AnalyticsDrawing] Calling pushEvent with payload:', payload)

                try {
                    // Find the main LiveView element and push to it
                    // liveSocket is available globally via window.liveSocket
                    const liveViewEl = document.querySelector('[data-phx-session]')
                    if (liveViewEl) {
                        console.log('[AnalyticsDrawing] Found LiveView element, pushing to it')
                        this.pushEventTo(liveViewEl, "save_edited_coordinates", payload)
                    } else {
                        console.log('[AnalyticsDrawing] No LiveView element found, using regular pushEvent')
                        this.pushEvent("save_edited_coordinates", payload)
                    }
                    console.log('[AnalyticsDrawing] pushEvent called successfully')
                } catch (e) {
                    console.error('[AnalyticsDrawing] pushEvent error:', e)
                }

                this.editMode = false
                this.editingShape = null
                this.canvas.style.cursor = 'default'
            }

            // Handle save trigger from server (when user clicks Save button in UI)
            this.handleEvent("trigger_save_edit", () => {
                console.log('[AnalyticsDrawing] trigger_save_edit received')
                this.saveEdit()
            })

            // Handle load_pending to restore pending shape when LiveView updates
            this.handleEvent("load_pending", ({ coordinates, mode }) => {
                console.log('[AnalyticsDrawing] load_pending event - restoring pending shape', coordinates)
                if (coordinates && coordinates.length > 0) {
                    this.pendingShape = {
                        type: mode === 'zone' ? 'zone' : 'line',
                        coordinates: coordinates,
                        color: [255, 255, 0, 150],
                        name: 'New Zone (pending)'
                    }
                    this.redraw()
                }
            })
        },

        resizeCanvas() {
            if (this.videoEl) {
                const rect = this.videoEl.getBoundingClientRect()
                this.canvas.width = rect.width
                this.canvas.height = rect.height

                // Simple direct mapping: normalized coordinates (0-1) map directly to canvas
                this.videoOffsetX = 0
                this.videoOffsetY = 0
                this.videoDisplayWidth = rect.width
                this.videoDisplayHeight = rect.height

                console.log('[AnalyticsDrawing] resizeCanvas (direct mode):', {
                    canvasW: rect.width, canvasH: rect.height
                })

                this.redraw()
            }
        },

        // Convert normalized coordinates (0-1) to canvas pixel coordinates
        normalizedToPixel(x, y) {
            const px = this.videoOffsetX + x * this.videoDisplayWidth
            const py = this.videoOffsetY + y * this.videoDisplayHeight
            return { x: px, y: py }
        },

        // Convert canvas pixel coordinates to normalized (0-1)
        pixelToNormalized(px, py) {
            const x = (px - this.videoOffsetX) / this.videoDisplayWidth
            const y = (py - this.videoOffsetY) / this.videoDisplayHeight
            return { x: Math.max(0, Math.min(1, x)), y: Math.max(0, Math.min(1, y)) }
        },

        startDrawing(mode) {
            this.drawingMode = mode
            this.isDrawing = true
            this.points = []
            this.canvas.style.cursor = 'crosshair'

            // Re-detect video/image element (may have changed)
            const videoId = this.el.dataset.videoId
            this.videoEl = document.getElementById(videoId)
            console.log('[AnalyticsDrawing] startDrawing mode:', mode, 'videoEl:', videoId, this.videoEl)

            // Resize canvas to match video/image
            this.resizeCanvas()
            this.redraw()
        },

        cancelDrawing() {
            this.drawingMode = null
            this.isDrawing = false
            this.points = []
            this.pendingShape = null  // Clear pending shape
            this.canvas.style.cursor = 'default'
            this.redraw()
        },

        handleClick(e) {
            e.preventDefault()
            e.stopPropagation()

            if (!this.isDrawing) return

            const rect = this.canvas.getBoundingClientRect()
            const x = (e.clientX - rect.left) / rect.width
            const y = (e.clientY - rect.top) / rect.height

            // Check if clicking near first point to close polygon
            if (this.drawingMode === 'zone' && this.points.length >= 3) {
                const firstPoint = this.points[0]
                const distance = Math.sqrt(
                    Math.pow((x - firstPoint.x) * rect.width, 2) +
                    Math.pow((y - firstPoint.y) * rect.height, 2)
                )
                if (distance < 15) {
                    this.finishDrawing()
                    return
                }
            }

            this.points.push({ x, y })
            this.redraw()
        },

        handleDoubleClick(e) {
            if (!this.isDrawing) return

            // For lines, finish on double-click if 2+ points
            if (this.drawingMode === 'line' && this.points.length >= 2) {
                this.finishDrawing()
            }
        },

        handleMouseMove(e) {
            const rect = this.canvas.getBoundingClientRect()
            const normalizedX = (e.clientX - rect.left) / rect.width
            const normalizedY = (e.clientY - rect.top) / rect.height

            // === EDIT MODE: Drag point ===
            if (this.editMode && this.isDragging && this.draggingPoint !== null) {
                const shape = this.existingShapes[this.editingShape.shapeIndex]
                if (shape) {
                    // Update point position (clamped to 0-1)
                    shape.coordinates[this.draggingPoint] = {
                        x: Math.max(0, Math.min(1, normalizedX)),
                        y: Math.max(0, Math.min(1, normalizedY))
                    }
                    this.redraw()
                }
                return
            }

            // === EDIT MODE: Change cursor on hover over points ===
            if (this.editMode && !this.isDragging) {
                const nearPoint = this.findNearestPoint(normalizedX, normalizedY)
                this.canvas.style.cursor = nearPoint !== null ? 'grab' : 'move'
                return
            }

            // === DRAWING MODE: Preview lines ===
            if (!this.isDrawing || this.points.length === 0) return

            this.redraw()

            // Draw preview line from last point to cursor
            const lastPoint = this.points[this.points.length - 1]
            this.ctx.beginPath()
            this.ctx.moveTo(lastPoint.x * this.canvas.width, lastPoint.y * this.canvas.height)
            this.ctx.lineTo(normalizedX * this.canvas.width, normalizedY * this.canvas.height)
            this.ctx.strokeStyle = 'rgba(255, 255, 0, 0.7)'
            this.ctx.lineWidth = 2
            this.ctx.setLineDash([5, 5])
            this.ctx.stroke()

            // For zones with 2+ points, also draw preview closing line from cursor to first point
            if (this.drawingMode === 'zone' && this.points.length >= 2) {
                const firstPoint = this.points[0]
                this.ctx.beginPath()
                this.ctx.moveTo(normalizedX * this.canvas.width, normalizedY * this.canvas.height)
                this.ctx.lineTo(firstPoint.x * this.canvas.width, firstPoint.y * this.canvas.height)
                this.ctx.strokeStyle = 'rgba(255, 255, 0, 0.5)'
                this.ctx.lineWidth = 2
                this.ctx.stroke()
            }

            this.ctx.setLineDash([])
        },

        // Find point near click position (for edit mode)
        findNearestPoint(normalizedX, normalizedY, threshold = 0.03) {
            if (!this.editMode || !this.editingShape) return null

            const shape = this.existingShapes[this.editingShape.shapeIndex]
            if (!shape) return null

            for (let i = 0; i < shape.coordinates.length; i++) {
                const point = shape.coordinates[i]
                const distance = Math.sqrt(
                    Math.pow(normalizedX - point.x, 2) +
                    Math.pow(normalizedY - point.y, 2)
                )
                if (distance < threshold) {
                    return i
                }
            }
            return null
        },

        handleMouseDown(e) {
            if (!this.editMode) return

            const rect = this.canvas.getBoundingClientRect()
            const normalizedX = (e.clientX - rect.left) / rect.width
            const normalizedY = (e.clientY - rect.top) / rect.height

            const pointIndex = this.findNearestPoint(normalizedX, normalizedY)
            if (pointIndex !== null) {
                this.isDragging = true
                this.draggingPoint = pointIndex
                this.canvas.style.cursor = 'grabbing'
                console.log('[AnalyticsDrawing] Started dragging point:', pointIndex)
            }
        },

        handleMouseUp(e) {
            if (this.isDragging) {
                console.log('[AnalyticsDrawing] Stopped dragging')
                this.isDragging = false
                this.draggingPoint = null
                this.canvas.style.cursor = this.editMode ? 'move' : 'default'
            }
        },

        finishDrawing() {
            console.log('[AnalyticsDrawing] finishDrawing called, points:', this.points.length)
            if (this.points.length < 2) {
                console.log('[AnalyticsDrawing] Not enough points, canceling')
                this.cancelDrawing()
                return
            }

            console.log('[AnalyticsDrawing] Pushing drawing_complete event', {
                mode: this.drawingMode,
                coordinates: this.points
            })

            // Push coordinates to LiveView
            this.pushEvent("drawing_complete", {
                mode: this.drawingMode,
                coordinates: this.points
            })

            console.log('[AnalyticsDrawing] Event pushed!')
            this.isDrawing = false
            this.canvas.style.cursor = 'default'

            // Keep points for preview - store as pending shape
            this.pendingShape = {
                type: this.drawingMode === 'zone' ? 'zone' : 'line',
                coordinates: [...this.points],
                color: [255, 255, 0, 150],
                name: 'New Zone (pending)'
            }
            this.points = []
            this.redraw()
        },

        redraw() {
            this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

            console.log('[redraw] existingShapes count:', this.existingShapes.length)

            // Draw existing shapes
            this.existingShapes.forEach((shape, idx) => {
                console.log(`[redraw] Drawing shape ${idx}:`, shape.name, shape.type, 'coords:', shape.coordinates.length)
                if (shape.type === 'zone') {
                    this.drawZone(shape.coordinates, shape.color || [255, 0, 0, 128], shape.name)
                } else {
                    this.drawLine(shape.coordinates, shape.color || [0, 255, 0, 255], shape.name, shape.direction)
                }
            })

            // Draw pending shape (after drawing complete, waiting for user to save)
            if (this.pendingShape) {
                if (this.pendingShape.type === 'zone') {
                    this.drawZone(this.pendingShape.coordinates, this.pendingShape.color, this.pendingShape.name)
                } else {
                    this.drawLine(this.pendingShape.coordinates, this.pendingShape.color, this.pendingShape.name)
                }
            }

            // Draw current drawing (while user is still clicking points)
            if (this.points.length > 0) {
                if (this.drawingMode === 'zone') {
                    this.drawZone(this.points, [255, 255, 0, 100], 'New Zone')
                } else {
                    this.drawLine(this.points, [255, 255, 0, 255], 'New Line')
                }
            }
        },

        drawZone(coords, color, name) {
            if (coords.length < 3) return  // Need at least 3 points for a polygon

            console.log('[drawZone] Drawing zone:', name, 'points:', coords.length)
            console.log('[drawZone] Raw coordinates:', JSON.stringify(coords))

            const [r, g, b, a] = color

            // Convert all coordinates to pixels first
            const pixelCoords = coords.map(c => this.normalizedToPixel(c.x, c.y))
            console.log('[drawZone] Pixel coordinates:', JSON.stringify(pixelCoords))

            // 1. Draw filled polygon with border in a single path
            this.ctx.beginPath()
            this.ctx.moveTo(pixelCoords[0].x, pixelCoords[0].y)
            for (let i = 1; i < pixelCoords.length; i++) {
                this.ctx.lineTo(pixelCoords[i].x, pixelCoords[i].y)
            }
            this.ctx.closePath()  // IMPORTANT: This closes the path back to the first point

            // Fill the polygon
            this.ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${a / 255 * 0.3})`
            this.ctx.fill()

            // Stroke the border (uses the same closed path)
            this.ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, 1)`
            this.ctx.lineWidth = 3
            this.ctx.setLineDash([])
            this.ctx.stroke()

            // 3. Draw corner points
            pixelCoords.forEach((p, i) => {
                this.ctx.beginPath()
                this.ctx.arc(p.x, p.y, 6, 0, Math.PI * 2)
                this.ctx.fillStyle = i === 0 ? '#00ff00' : '#ffffff'
                this.ctx.fill()
                this.ctx.strokeStyle = '#000'
                this.ctx.lineWidth = 1
                this.ctx.stroke()
            })

            // 4. Draw name label at CENTER of polygon
            if (name && coords.length > 0) {
                // Calculate center of polygon
                const avgX = coords.reduce((sum, c) => sum + c.x, 0) / coords.length
                const avgY = coords.reduce((sum, c) => sum + c.y, 0) / coords.length
                const center = this.normalizedToPixel(avgX, avgY)

                this.ctx.font = 'bold 14px Arial'
                const textMetrics = this.ctx.measureText(name)
                const textWidth = textMetrics.width
                const textHeight = 16
                const padding = 6

                // Background box
                this.ctx.fillStyle = `rgba(${r}, ${g}, ${b}, 0.85)`
                this.ctx.fillRect(
                    center.x - textWidth / 2 - padding,
                    center.y - textHeight / 2 - padding,
                    textWidth + padding * 2,
                    textHeight + padding * 2
                )

                // Text
                this.ctx.fillStyle = '#fff'
                this.ctx.textAlign = 'center'
                this.ctx.textBaseline = 'middle'
                this.ctx.fillText(name, center.x, center.y)

                // Reset
                this.ctx.textAlign = 'left'
                this.ctx.textBaseline = 'alphabetic'
            }
        },

        drawLine(coords, color, name, direction = 'Both') {
            if (coords.length < 2) return

            const [r, g, b, a] = color

            // Draw line segments
            this.ctx.beginPath()
            let p0 = this.normalizedToPixel(coords[0].x, coords[0].y)
            this.ctx.moveTo(p0.x, p0.y)
            for (let i = 1; i < coords.length; i++) {
                let p = this.normalizedToPixel(coords[i].x, coords[i].y)
                this.ctx.lineTo(p.x, p.y)
            }
            this.ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${a / 255})`
            this.ctx.lineWidth = 3
            this.ctx.stroke()

            // Draw points
            coords.forEach((coord, i) => {
                let p = this.normalizedToPixel(coord.x, coord.y)
                this.ctx.beginPath()
                this.ctx.arc(p.x, p.y, 6, 0, Math.PI * 2)
                this.ctx.fillStyle = '#ffffff'
                this.ctx.fill()
                this.ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, 1)`
                this.ctx.lineWidth = 2
                this.ctx.stroke()
            })

            // Draw direction arrows perpendicular to line
            if (coords.length >= 2) {
                const midIdx = Math.floor(coords.length / 2)
                const c1 = coords[midIdx - 1] || coords[0]
                const c2 = coords[midIdx]
                const p1 = this.normalizedToPixel(c1.x, c1.y)
                const p2 = this.normalizedToPixel(c2.x, c2.y)
                const midX = (p1.x + p2.x) / 2
                const midY = (p1.y + p2.y) / 2
                // Calculate angle perpendicular to line
                const lineAngle = Math.atan2(p2.y - p1.y, p2.x - p1.x)
                const perpAngle = lineAngle + Math.PI / 2  // Perpendicular (90 degrees)

                const arrowSize = 12
                const arrowOffset = 20  // Distance from center of line

                // Draw Up arrow (pointing perpendicular upward from line)
                if (direction === 'Up' || direction === 'Both') {
                    const upX = midX + Math.cos(perpAngle) * arrowOffset
                    const upY = midY + Math.sin(perpAngle) * arrowOffset
                    this.ctx.save()
                    this.ctx.translate(upX, upY)
                    this.ctx.rotate(perpAngle - Math.PI / 2)  // Point upward relative to perpendicular
                    this.ctx.beginPath()
                    this.ctx.moveTo(0, -arrowSize)
                    this.ctx.lineTo(-arrowSize / 2, 0)
                    this.ctx.lineTo(arrowSize / 2, 0)
                    this.ctx.closePath()
                    this.ctx.fillStyle = `rgba(${r}, ${g}, ${b}, 1)`
                    this.ctx.fill()
                    this.ctx.strokeStyle = '#fff'
                    this.ctx.lineWidth = 1
                    this.ctx.stroke()
                    this.ctx.restore()
                }

                // Draw Down arrow (pointing opposite perpendicular direction)
                if (direction === 'Down' || direction === 'Both') {
                    const downX = midX - Math.cos(perpAngle) * arrowOffset
                    const downY = midY - Math.sin(perpAngle) * arrowOffset
                    this.ctx.save()
                    this.ctx.translate(downX, downY)
                    this.ctx.rotate(perpAngle + Math.PI / 2)  // Point downward relative to perpendicular
                    this.ctx.beginPath()
                    this.ctx.moveTo(0, -arrowSize)
                    this.ctx.lineTo(-arrowSize / 2, 0)
                    this.ctx.lineTo(arrowSize / 2, 0)
                    this.ctx.closePath()
                    this.ctx.fillStyle = `rgba(${r}, ${g}, ${b}, 1)`
                    this.ctx.fill()
                    this.ctx.strokeStyle = '#fff'
                    this.ctx.lineWidth = 1
                    this.ctx.stroke()
                    this.ctx.restore()
                }
            }

            // Draw name
            if (name && coords.length >= 2) {
                const avgX = (coords[0].x + coords[coords.length - 1].x) / 2
                const avgY = (coords[0].y + coords[coords.length - 1].y) / 2
                const mid = this.normalizedToPixel(avgX, avgY)
                this.ctx.font = '12px Arial'
                this.ctx.fillStyle = '#fff'
                this.ctx.strokeStyle = '#000'
                this.ctx.lineWidth = 2
                this.ctx.strokeText(name, mid.x - 20, mid.y - 15)
                this.ctx.fillText(name, mid.x - 20, mid.y - 15)
            }
        },

        // Called when LiveView re-renders - redraw shapes to preserve them
        updated() {
            console.log('[AnalyticsDrawing] updated() - redrawing shapes after re-render')
            this.resizeCanvas()
            this.redraw()
        },

        destroyed() {
            window.removeEventListener('resize', this.resizeCanvas.bind(this))
        }
    },
    ...getHooks(liveVueApp)
}

let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
    params: { _csrf_token: csrfToken },
    hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Listen for reload-popovers events and re-init the popovers
// phx-loading-xxx events are not triggered by push_patch
// so this is why we listen for this custom event instead
window.addEventListener('phx:reload-popovers', (e) => initPopovers())

window.addEventListener("phx:js-exec", ({ detail }) => {
    document.querySelectorAll(detail.to).forEach((el) => {
        liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
})

window.addEventListener("phx:download-footage", (e) => downloadFile(e.detail.url))

window.addEventListener("events:clipboard-copy", (e) => {
    navigator.clipboard.writeText(e.target.innerText)

    const toggleIcon = () => {
        e.detail.dispatcher.querySelector(".copy-icon")?.classList.toggle("hidden")
        e.detail.dispatcher.querySelector(".copied-icon")?.classList.toggle("hidden")
    }

    toggleIcon()
    setTimeout(toggleIcon, 1500)
})

window.addEventListener("events:play-clip", (e) => {
    startStreaming(e.target.id, e.detail.src, e.detail.poster)
})

function startStreaming(elem_id, src, poster_url) {
    var video = document.getElementById(elem_id)
    if (video != null && Hls.isSupported()) {
        if (window.hls) {
            window.hls.destroy()
        }

        if (poster_url != null) {
            video.poster = poster_url
        }

        window.hls = new Hls({
            manifestLoadingTimeOut: 60_000,
        })
        window.hls.loadSource(src)
        window.hls.attachMedia(video)

        window.hls.on(Hls.Events.ERROR, (event, data) => {
            // handle error
            console.log(data)
        })
    }
}

function downloadFile(url) {
    const anchor = document.createElement("a");
    anchor.style.display = "none";
    anchor.href = url;
    anchor.target = "_blank"

    document.body.appendChild(anchor);
    anchor.click();

    document.body.removeChild(anchor);
}

(function () {
    const lightSwitch = document.getElementById("light-switch")
    if (localStorage.getItem('dark-mode') === 'true' || (!('dark-mode' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        lightSwitch.checked = true;
    } else {
        lightSwitch.checked = false;
    }
})()
