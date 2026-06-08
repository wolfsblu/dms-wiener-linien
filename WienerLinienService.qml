pragma Singleton
import QtQuick

Item {
    id: root

    // ---- Settings — written by any PluginComponent instance via configure() ----
    property var trackedStops: []
    property int pollMs: 60000

    // ---- Output — read by all PluginComponent instances ----
    property var departuresByStation: []
    property string lastError: ""
    // Unfiltered map of all towards values seen per station+line — persists across fetches
    // { stationName: { lineName: [towards, ...] } }
    property var knownDirections: {}

    // ---- Internal ----
    property bool _rateLimited: false
    property real _rateLimitEndsMs: 0
    property real _lastFetchMs: 0
    readonly property int _minIntervalMs: 15000

    WienerLinienClient { id: client }

    // Called by every PluginComponent instance when its settings change.
    // All instances share the same pluginData, so the values are always identical;
    // calling this from multiple instances is safe and idempotent.
    function configure(stops, intervalMs) {
        root.trackedStops = stops
        root.pollMs = Math.max(30000, intervalMs)
        settingsDebounce.restart()
    }

    function _collectStopIds() {
        const ids = []
        for (let i = 0; i < root.trackedStops.length; i++) {
            const sids = root.trackedStops[i].stopIds || []
            for (let j = 0; j < sids.length; j++) ids.push(sids[j])
        }
        return ids
    }

    function _buildRblIndex() {
        const m = {}
        for (let i = 0; i < root.trackedStops.length; i++) {
            const sids = root.trackedStops[i].stopIds || []
            for (let j = 0; j < sids.length; j++) m[sids[j]] = i
        }
        return m
    }

    function _parseMonitors(monitors) {
        const rblIdx = root._buildRblIndex()
        const result = root.trackedStops.map(function (s) {
            return { stationName: s.name, lines: [] }
        })

        // Accumulate all known directions before any filtering
        const known = Object.assign({}, root.knownDirections)
        for (let m = 0; m < monitors.length; m++) {
            const mon = monitors[m]
            const props = mon.locationStop && mon.locationStop.properties
            const rbl = props && props.attributes && props.attributes.rbl
            const idx = rblIdx[rbl]
            if (idx === undefined || idx === null) continue
            const stName = root.trackedStops[idx].name
            if (!known[stName]) known[stName] = {}
            const rawLines = mon.lines || []
            for (let l = 0; l < rawLines.length; l++) {
                const rl = rawLines[l]
                if (!rl.name || !rl.towards) continue
                if (!known[stName][rl.name]) known[stName][rl.name] = []
                if (known[stName][rl.name].indexOf(rl.towards) === -1)
                    known[stName][rl.name].push(rl.towards)
            }
        }
        root.knownDirections = known

        for (let m = 0; m < monitors.length; m++) {
            const mon = monitors[m]
            const props = mon.locationStop && mon.locationStop.properties
            const rbl = props && props.attributes && props.attributes.rbl
            const idx = rblIdx[rbl]
            if (idx === undefined || idx === null) continue

            const lines = mon.lines || []
            for (let l = 0; l < lines.length; l++) {
                const line = lines[l]
                const deps = (line.departures && line.departures.departure) || []
                if (deps.length === 0) continue
                const cd0 = deps[0].departureTime && deps[0].departureTime.countdown
                if (cd0 === undefined || cd0 === null) continue

                const lineFilter = root.trackedStops[idx].lines || []
                if (lineFilter.length > 0 && lineFilter.indexOf(line.name) === -1) continue

                const excl = (root.trackedStops[idx].directions || {})[line.name]
                if (excl && excl.indexOf(line.towards) !== -1) continue

                let dup = null
                for (let k = 0; k < result[idx].lines.length; k++) {
                    if (result[idx].lines[k].name === line.name
                            && result[idx].lines[k].towards === line.towards) {
                        dup = result[idx].lines[k]
                        break
                    }
                }

                if (dup) {
                    if (cd0 < dup.departures[0].countdown)
                        dup.departures[0].countdown = cd0
                    continue
                }

                result[idx].lines.push({
                    name:        line.name || "",
                    towards:     line.towards || "",
                    type:        line.type || "ptBus",
                    barrierFree: line.barrierFree === true,
                    departures:  deps.slice(0, 3).map(function (d) {
                        return {
                            countdown:   (d.departureTime && d.departureTime.countdown) || 0,
                            timeReal:    (d.departureTime && d.departureTime.timeReal) || "",
                            timePlanned: (d.departureTime && d.departureTime.timePlanned) || ""
                        }
                    })
                })
            }
        }

        const typeOrder = { ptMetro: 0, ptTram: 1, ptBus: 2, ptBusNight: 3 }
        for (let i = 0; i < result.length; i++) {
            result[i].lines.sort(function (a, b) {
                const ta = typeOrder[a.type] !== undefined ? typeOrder[a.type] : 9
                const tb = typeOrder[b.type] !== undefined ? typeOrder[b.type] : 9
                if (ta !== tb) return ta - tb
                return a.departures[0].countdown - b.departures[0].countdown
            })
        }
        return result
    }

    function refresh() {
        if (root._rateLimited) return
        const now = Date.now()
        if (now - root._lastFetchMs < root._minIntervalMs) return
        const ids = root._collectStopIds()
        if (ids.length === 0) {
            root.departuresByStation = []
            root.lastError = ""
            return
        }
        root._lastFetchMs = now
        client.fetchMonitor(ids, function (err, monitors) {
            if (err) {
                const msg = (err && err.message) ? err.message : String(err)
                console.warn("[transit] poll failed:", msg)
                const isRateLimited = (err.httpStatus === 429) || (err.apiCode === 316)
                if (isRateLimited) {
                    root._rateLimited = true
                    root._rateLimitEndsMs = Date.now() + rateLimitBackoff.interval
                    root.lastError = "Rate limited — retrying in 5:00"
                    rateLimitBackoff.restart()
                    countdownTicker.restart()
                } else {
                    root.lastError = msg
                }
                return
            }
            root.lastError = ""
            root._rateLimited = false
            root.departuresByStation = root._parseMonitors(monitors)
        })
    }

    Component.onCompleted: refresh()

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        id: settingsDebounce
        interval: 600
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: rateLimitBackoff
        interval: 300000
        repeat: false
        onTriggered: {
            root._rateLimited = false
            countdownTicker.stop()
            root.refresh()
        }
    }

    Timer {
        id: countdownTicker
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            const remaining = Math.max(0, Math.ceil((root._rateLimitEndsMs - Date.now()) / 1000))
            const mins = Math.floor(remaining / 60)
            const secs = remaining % 60
            root.lastError = "Rate limited — retrying in " + mins + ":" + (secs < 10 ? "0" : "") + secs
        }
    }
}
