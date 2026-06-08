import QtQuick

// HTTP wrapper for the Wiener Linien Realtime API (v1.5).
// All requests are unauthenticated GET calls to /ogd_realtime/monitor.
// Callbacks follow node-style: cb(err, result); err is null on success.
QtObject {
    id: root

    readonly property string _base: "http://www.wienerlinien.at/ogd_realtime"

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
        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const body = JSON.parse(xhr.responseText)
                    const apiCode = (body && body.message && body.message.messageCode) || 0
                    if (apiCode !== 0) {
                        const err = new Error("API code " + apiCode)
                        err.httpStatus = xhr.status
                        err.apiCode = apiCode
                        cb(err)
                        return
                    }
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
