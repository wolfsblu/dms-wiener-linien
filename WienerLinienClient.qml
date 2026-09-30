import QtQuick
import Quickshell

// HTTP wrapper for the Wiener Linien Realtime API (v1.5).
// All requests are unauthenticated GET calls to /ogd_realtime/monitor.
// Callbacks follow node-style: cb(err, result); err is null on success.
QtObject {
    id: root

    readonly property string _base: "https://www.wienerlinien.at/ogd_realtime"

    // Verbose request/response logging is opt-in: set WIENER_LINIEN_DEBUG=1
    // in the shell environment to avoid flooding the log on every poll.
    readonly property bool _debug: Quickshell.env("WIENER_LINIEN_DEBUG") === "1"

    // Fetch departure monitor for one or more RBL stop IDs.
    // cb(null, monitors[]) on success, cb(Error) on failure.
    function fetchMonitor(stopIds, cb) {
        if (!stopIds || stopIds.length === 0) {
            cb(null, [])
            return
        }
        let url = _base + "/monitor?"
        for (let i = 0; i < stopIds.length; i++) {
            if (i > 0) url += "&"
            url += "stopId=" + encodeURIComponent(String(stopIds[i]))
        }
        const requestHeaders = { "Accept": "application/json" }

        if (root._debug) {
            console.info("[transit] --> GET", url)
            console.info("[transit] --> Headers:", JSON.stringify(requestHeaders))
        }

        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Accept", requestHeaders["Accept"])
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            if (root._debug) {
                console.info("[transit] <-- Status:", xhr.status, xhr.statusText)
                console.info("[transit] <-- Headers:", xhr.getAllResponseHeaders())
                console.info("[transit] <-- Body:", xhr.responseText)
            }

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const body = JSON.parse(xhr.responseText)
                    cb(null, (body && body.data && body.data.monitors) || [])
                } catch (e) {
                    cb(e)
                }
            } else {
                let code = 0
                try { code = JSON.parse(xhr.responseText).message.messageCode } catch (_) {}
                const err = new Error("API error " + xhr.status + " (code " + code + ")")
                err.httpStatus = xhr.status
                err.apiCode = code
                cb(err)
            }
        }
        xhr.send(null)
    }
}
