import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ---- Settings (from PublicTransitSettings.qml via pluginData) ----
    readonly property var trackedStops: {
        try { return JSON.parse(pluginData.trackedStopsJson || "[]") }
        catch (_) { return [] }
    }
    readonly property int pollMs: Math.max(30000, parseInt(pluginData.pollInterval || "60") * 1000)

    // ---- Runtime state ----
    property var departuresByStation: []
    property string lastError: ""

    // ---- API client ----
    WienerLinienClient { id: client }

    // ---- Helpers ----

    function lineColor(name, type) {
        if (type === "ptMetro" || (name && name.charAt(0) === "U")) {
            switch (name) {
                case "U1": return "#e2001a"
                case "U2": return "#9b2f83"
                case "U3": return "#f47d00"
                case "U4": return "#006f3c"
                case "U6": return "#9b6b34"
                default:   return "#444444"
            }
        }
        if (type === "ptTram")     return "#cd1518"
        if (type === "ptBusNight") return "#22375b"
        return "#1d5a96"
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

                // Deduplicate by line name + towards; keep lowest countdown
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

        // Sort each station's lines: metro → tram → bus → night bus; then by countdown
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

    property bool _rateLimited: false
    property real _lastFetchMs: 0
    readonly property int _minIntervalMs: 15000

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
                    root.lastError = "Rate limited — retrying in 5 min"
                    rateLimitBackoff.restart()
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
    onTrackedStopsChanged: settingsDebounce.restart()

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

    // Wait 5 minutes after a 429 before trying again
    Timer {
        id: rateLimitBackoff
        interval: 300000
        repeat: false
        onTriggered: {
            root._rateLimited = false
            root.refresh()
        }
    }

    // ---- Inline components ----

    component LineBadge: Rectangle {
        id: badge
        required property string lineName
        required property string lineType
        property int fontSize: Theme.fontSizeSmall

        readonly property color _bg: root.lineColor(lineName, lineType)
        color: _bg
        radius: 4
        implicitWidth: _label.implicitWidth + 8
        implicitHeight: _label.implicitHeight + 4

        StyledText {
            id: _label
            anchors.centerIn: parent
            text: badge.lineName
            color: "white"
            font.pixelSize: badge.fontSize
            font.weight: Font.Bold
        }
    }

    // ---- Bar pills ----

    horizontalBarPill: Component {
        Row {
            id: hpill
            spacing: Theme.spacingS

            DankIcon {
                name: "directions_transit"
                size: Theme.iconSizeSmall
                color: root.trackedStops.length === 0
                    ? Theme.surfaceVariantText : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.trackedStops.length === 0
                text: "No stops"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: root.departuresByStation
                delegate: Row {
                    id: stationChips
                    required property var modelData
                    required property int index
                    spacing: 4
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    StyledText {
                        visible: stationChips.index > 0
                        text: "·"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Top 2 lines for this station
                    Repeater {
                        model: modelData.lines ? modelData.lines.slice(0, 2) : []
                        delegate: Row {
                            required property var modelData
                            spacing: 3
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                            LineBadge {
                                lineName: modelData.name
                                lineType: modelData.type
                                fontSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: modelData.departures[0].countdown + "′"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // No departures yet for this station
                    StyledText {
                        visible: !modelData.lines || modelData.lines.length === 0
                        text: modelData.stationName + " —"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            DankIcon {
                name: "directions_transit"
                size: Theme.iconSizeSmall
                color: root.trackedStops.length === 0
                    ? Theme.surfaceVariantText : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.trackedStops.length.toString()
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---- Popout ----

    popoutContent: Component {
        FocusScope {
            id: contentFocusScope
            width: parent ? parent.width : 0
            implicitHeight: mainContent.implicitHeight
            focus: true

            property var closePopout: null
            property var parentPopout: null

            PopoutComponent {
                id: mainContent
                width: parent.width
                closePopout: contentFocusScope.closePopout
                headerText: "Public Transit"
                detailsText: {
                    if (root.trackedStops.length === 0) return "No stops configured"
                    const n = root.trackedStops.length
                    return n + " stop" + (n === 1 ? "" : "s") + " tracked"
                }
                showCloseButton: true

                Flickable {
                    width: parent.width
                    height: Math.min(580, boardCol.implicitHeight)
                    contentHeight: boardCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: boardCol
                        width: parent.width
                        spacing: Theme.spacingL
                        topPadding: Theme.spacingS
                        bottomPadding: Theme.spacingS

                        // Error banner
                        Rectangle {
                            visible: root.lastError.length > 0
                            width: boardCol.width
                            height: errText.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.1)
                            border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.3)
                            border.width: 1

                            StyledText {
                                id: errText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                text: root.lastError
                                color: Theme.error
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Empty state
                        StyledText {
                            visible: root.trackedStops.length === 0
                            width: boardCol.width
                            text: "Open Settings → Plugins → Public Transit Tracker to add stops."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // One section per tracked station
                        Repeater {
                            model: root.departuresByStation
                            delegate: Column {
                                required property var modelData
                                width: boardCol.width
                                spacing: Theme.spacingXS

                                // Station header
                                Row {
                                    spacing: Theme.spacingXS
                                    leftPadding: Theme.spacingXS

                                    DankIcon {
                                        name: "place"
                                        size: Theme.iconSizeSmall
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: modelData.stationName
                                        color: Theme.primary
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                StyledText {
                                    visible: !modelData.lines || modelData.lines.length === 0
                                    text: "No departures available"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    leftPadding: Theme.spacingM
                                }

                                // Line rows
                                Repeater {
                                    model: modelData.lines || []
                                    delegate: Item {
                                        required property var modelData
                                        width: boardCol.width
                                        height: Math.max(36, _towards.implicitHeight + Theme.spacingXS * 2)

                                        LineBadge {
                                            id: _badge
                                            lineName: modelData.name
                                            lineType: modelData.type
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        // Barrier-free icon
                                        DankIcon {
                                            visible: modelData.barrierFree
                                            name: "accessible"
                                            size: 14
                                            color: Theme.surfaceVariantText
                                            anchors.left: _badge.right
                                            anchors.leftMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            id: _towards
                                            text: "→ " + modelData.towards
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                            anchors.left: _badge.right
                                            anchors.leftMargin: modelData.barrierFree ? 22 : Theme.spacingS
                                            anchors.right: _countdowns.left
                                            anchors.rightMargin: Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Row {
                                            id: _countdowns
                                            spacing: Theme.spacingXS
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter

                                            Repeater {
                                                model: modelData.departures || []
                                                delegate: StyledText {
                                                    required property var modelData
                                                    required property int index
                                                    text: (index > 0 ? "/ " : "") + modelData.countdown + " min"
                                                    color: index === 0
                                                        ? (modelData.countdown <= 1 ? Theme.error
                                                            : modelData.countdown <= 3 ? Theme.warning
                                                            : Theme.surfaceVariantText)
                                                        : Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: index === 0 ? Font.Bold : Font.Normal
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 540
}
