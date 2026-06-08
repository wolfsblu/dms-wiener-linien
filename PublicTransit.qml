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

    // Push settings into the singleton whenever they change.
    // All screen instances share the same pluginData so the values are always identical.
    Component.onCompleted: WienerLinienService.configure(trackedStops, pollMs)
    onTrackedStopsChanged: WienerLinienService.configure(trackedStops, pollMs)
    onPollMsChanged: WienerLinienService.configure(trackedStops, pollMs)

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
                model: WienerLinienService.departuresByStation
                delegate: Row {
                    id: stationChips
                    required property var modelData
                    required property int index
                    spacing: 4
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

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
                headerText: "Wiener Linien"
                detailsText: ""
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
                            visible: WienerLinienService.lastError.length > 0
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
                                text: WienerLinienService.lastError
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
                            model: WienerLinienService.departuresByStation
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
                                            text: modelData.towards
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
