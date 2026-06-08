import QtQuick
import QtQuick.Controls
import "data/stations.js" as StationsData
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wienerLinien"

    function lineColor(name) {
        if (name && name.charAt(0) === "U") {
            switch (name) {
                case "U1": return "#e2001a"
                case "U2": return "#9b2f83"
                case "U3": return "#f47d00"
                case "U4": return "#006f3c"
                case "U6": return "#9b6b34"
                default:   return "#444444"
            }
        }
        if (name && name.charAt(0) >= "0" && name.charAt(0) <= "9") return "#cd1518"
        return "#1d5a96"
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Poll interval"
        description: "How often to refresh departure times."
        options: [
            { label: "30 seconds",  value: "30" },
            { label: "1 minute",    value: "60" },
            { label: "2 minutes",   value: "120" },
            { label: "5 minutes",   value: "300" }
        ]
        defaultValue: "60"
    }

    StyledText {
        text: "Tracked Lines"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        text: "Search for a station, then tap line badges to select which lines to track. Tap a tracked station to edit its lines and directions."
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
        width: parent ? parent.width : 400
    }

    Item {
        id: picker
        width: parent ? parent.width : 400
        implicitHeight: pickerCol.implicitHeight

        property var allStations: []
        property string searchText: ""
        // [{ name, stopIds, lines: string[], directions: {lineName: towards|null} }]
        property var selectedStations: []
        property string expandedStation: ""

        property var filteredStations: {
            const q = picker.searchText.toLowerCase().trim()
            if (q.length < 2) return []
            return picker.allStations.filter(function(s) {
                return s.name.toLowerCase().indexOf(q) !== -1
            }).slice(0, 12)
        }

        function loadValue() {
            try {
                picker.selectedStations = JSON.parse(root.loadValue("trackedStopsJson", "[]"))
            } catch (e) {
                picker.selectedStations = []
            }
        }

        function save() {
            root.saveValue("trackedStopsJson", JSON.stringify(picker.selectedStations))
        }

        function trackedEntry(stationName) {
            for (let i = 0; i < picker.selectedStations.length; i++)
                if (picker.selectedStations[i].name === stationName)
                    return picker.selectedStations[i]
            return null
        }

        function isLineTracked(stationName, lineName) {
            const e = picker.trackedEntry(stationName)
            return e ? e.lines.indexOf(lineName) !== -1 : false
        }

        function toggleLine(stationObj, lineName) {
            let next = picker.selectedStations.slice()
            let found = false
            for (let i = 0; i < next.length; i++) {
                if (next[i].name !== stationObj.name) continue
                found = true
                const lines = next[i].lines.slice()
                const li = lines.indexOf(lineName)
                const dirs = Object.assign({}, next[i].directions || {})
                if (li !== -1) {
                    lines.splice(li, 1)
                    delete dirs[lineName]
                } else {
                    lines.push(lineName)
                }
                if (lines.length === 0)
                    next.splice(i, 1)
                else
                    next[i] = { name: next[i].name, stopIds: next[i].stopIds,
                                lines: lines, directions: dirs }
                break
            }
            if (!found)
                next.push({ name: stationObj.name, stopIds: stationObj.stopIds,
                            lines: [lineName], directions: {} })
            picker.selectedStations = next
            picker.save()
        }

        // Toggle a direction in/out of the exclusion list for a line.
        // availDirs is the full set of known directions for this line.
        function toggleDirection(stationName, lineName, towards, availDirs) {
            let next = picker.selectedStations.slice()
            for (let i = 0; i < next.length; i++) {
                if (next[i].name !== stationName) continue
                const dirs = Object.assign({}, next[i].directions || {})
                let excl = (dirs[lineName] || []).slice()
                const pos = excl.indexOf(towards)
                if (pos !== -1) excl.splice(pos, 1)   // was excluded → re-include
                else excl.push(towards)               // was included → exclude
                if (excl.length === 0) delete dirs[lineName]
                else dirs[lineName] = excl
                next[i] = { name: next[i].name, stopIds: next[i].stopIds,
                            lines: next[i].lines, directions: dirs }
                break
            }
            picker.selectedStations = next
            picker.save()
        }

        // Returns true if a direction is currently included (not excluded) for a line
        function isDirActive(stationName, lineName, towards) {
            const e = picker.trackedEntry(stationName)
            if (!e) return true
            const excl = (e.directions || {})[lineName]
            if (!excl) return true
            return excl.indexOf(towards) === -1
        }

        function removeStation(name) {
            picker.selectedStations = picker.selectedStations.filter(function(s) {
                return s.name !== name
            })
            picker.save()
        }

        function allLinesFor(stationName) {
            for (let i = 0; i < picker.allStations.length; i++)
                if (picker.allStations[i].name === stationName)
                    return picker.allStations[i].lines || []
            return []
        }

        // Returns all known towards values for a line at a station (persists across fetches)
        function availableDirections(stationName, lineName) {
            const known = WienerLinienService.knownDirections
            return (known[stationName] && known[stationName][lineName]) || []
        }

        Component.onCompleted: {
            picker.allStations = StationsData.stations
            picker.loadValue()
        }

        Column {
            id: pickerCol
            width: parent.width
            spacing: Theme.spacingXS

            // ---- Tracked stations ----
            Repeater {
                model: picker.selectedStations
                delegate: Column {
                    id: _trackedItem
                    required property var modelData
                    readonly property var station: modelData
                    readonly property bool expanded: picker.expandedStation === station.name

                    width: pickerCol.width
                    spacing: 2

                    Rectangle {
                        width: _trackedItem.width
                        implicitHeight: Math.max(40, _nameRow.implicitHeight + Theme.spacingS * 2)
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 40
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.expandedStation =
                                _trackedItem.expanded ? "" : _trackedItem.station.name
                        }

                        Flow {
                            id: _nameRow
                            anchors.left: parent.left
                            anchors.right: _removeBtn.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            StyledText {
                                text: _trackedItem.station.name
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: _trackedItem.station.lines
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property string lineName: modelData
                                    readonly property var dirs: _trackedItem.station.directions || {}
                                    readonly property string dirLabel: dirs[lineName] || ""

                                    color: root.lineColor(lineName)
                                    radius: 4
                                    implicitWidth: _bt.implicitWidth + 8
                                    implicitHeight: _bt.implicitHeight + 4

                                    Row {
                                        id: _bt
                                        anchors.centerIn: parent
                                        spacing: 3
                                        StyledText {
                                            text: parent.parent.lineName
                                            color: "white"
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            font.weight: Font.Bold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            visible: parent.parent.dirLabel.length > 0
                                            text: "→ " + parent.parent.dirLabel
                                            color: Qt.rgba(1, 1, 1, 0.8)
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: _removeBtn
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: _rmMouse.containsMouse
                                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                                : "transparent"
                            DankIcon { name: "close"; size: 14; color: Theme.error; anchors.centerIn: parent }
                            MouseArea {
                                id: _rmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.removeStation(_trackedItem.station.name)
                            }
                        }
                    }

                    // Expanded editor: line toggles + direction picker per line
                    Rectangle {
                        visible: _trackedItem.expanded
                        width: _trackedItem.width
                        implicitHeight: _editCol.implicitHeight + Theme.spacingM * 2
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                        radius: Theme.cornerRadius

                        Column {
                            id: _editCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            // One row per available line: [badge toggle]  [dir chip] [dir chip] …
                            Repeater {
                                model: picker.allLinesFor(_trackedItem.station.name)
                                delegate: Flow {
                                    id: _lineRow
                                    required property string modelData
                                    readonly property string lineName: modelData
                                    readonly property bool tracked:
                                        picker.isLineTracked(_trackedItem.station.name, lineName)
                                    readonly property var availDirs:
                                        picker.availableDirections(_trackedItem.station.name, lineName)

                                    width: _editCol.width
                                    spacing: 6

                                    // Line badge — acts as the toggle
                                    Rectangle {
                                        color: _lineRow.tracked ? root.lineColor(_lineRow.lineName)
                                                                : Qt.rgba(0.5, 0.5, 0.5, 0.15)
                                        radius: 4
                                        implicitWidth: _lt.implicitWidth + 12
                                        implicitHeight: _lt.implicitHeight + 8
                                        border.color: _lineRow.tracked ? "transparent"
                                                                       : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                                        border.width: 1
                                        StyledText {
                                            id: _lt
                                            anchors.centerIn: parent
                                            text: _lineRow.lineName
                                            color: _lineRow.tracked ? "white" : Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: picker.toggleLine(
                                                { name: _trackedItem.station.name,
                                                  stopIds: _trackedItem.station.stopIds },
                                                _lineRow.lineName)
                                        }
                                    }

                                    // Direction chips — only shown when line is tracked
                                    Repeater {
                                        model: _lineRow.tracked ? _lineRow.availDirs : []
                                        delegate: Rectangle {
                                            required property string modelData
                                            readonly property string towards: modelData
                                            readonly property bool active:
                                                picker.isDirActive(_trackedItem.station.name,
                                                                   _lineRow.lineName, towards)

                                            color: active
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                                                : Qt.rgba(0.5, 0.5, 0.5, 0.12)
                                            radius: 4
                                            implicitWidth: _dct.implicitWidth + 12
                                            implicitHeight: _dct.implicitHeight + 8
                                            border.color: active ? "transparent"
                                                                 : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                                            border.width: 1
                                            StyledText {
                                                id: _dct
                                                anchors.centerIn: parent
                                                text: parent.towards
                                                color: parent.active ? "white" : Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: picker.toggleDirection(
                                                    _trackedItem.station.name,
                                                    _lineRow.lineName,
                                                    parent.towards,
                                                    _lineRow.availDirs)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- Search field ----
            Rectangle {
                width: pickerCol.width
                height: _searchRow.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.surface
                border.color: _searchField.activeFocus ? Theme.primary : Qt.rgba(0, 0, 0, 0.12)
                border.width: 1

                Row {
                    id: _searchRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "search"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextField {
                        id: _searchField
                        width: parent.width - Theme.iconSizeSmall - Theme.spacingXS
                        placeholderText: "Search station..."
                        color: Theme.surfaceText
                        placeholderTextColor: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        background: null
                        onTextChanged: {
                            picker.searchText = text
                            picker.expandedStation = ""
                        }
                    }
                }
            }

            // ---- Search results ----
            Repeater {
                model: picker.filteredStations
                delegate: Column {
                    id: _searchResult
                    required property var modelData
                    readonly property var stationData: modelData
                    readonly property bool hasTracked: picker.trackedEntry(stationData.name) !== null
                    readonly property bool expanded: picker.expandedStation === stationData.name

                    width: pickerCol.width
                    spacing: 2

                    Rectangle {
                        width: _searchResult.width
                        height: _resRow.implicitHeight + Theme.spacingXS * 2
                        radius: Theme.cornerRadius
                        color: _searchResult.hasTracked
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                            : (_resMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : "transparent")

                        Row {
                            id: _resRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            DankIcon {
                                visible: _searchResult.hasTracked
                                name: "check_circle"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: _searchResult.stationData.name
                                color: _searchResult.hasTracked ? Theme.primary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: (_searchResult.stationData.lines || []).slice(0, 6).join(", ")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall - 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: _resMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.expandedStation =
                                _searchResult.expanded ? "" : _searchResult.stationData.name
                        }
                    }

                    // Line selection panel
                    Rectangle {
                        visible: _searchResult.expanded
                        width: _searchResult.width
                        implicitHeight: _lineFlow.implicitHeight + Theme.spacingS * 2
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                        radius: Theme.cornerRadius

                        Flow {
                            id: _lineFlow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingS
                            spacing: 6

                            Repeater {
                                model: _searchResult.stationData.lines || []
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property string lineName: modelData
                                    readonly property bool tracked:
                                        picker.isLineTracked(_searchResult.stationData.name, lineName)

                                    color: tracked ? root.lineColor(lineName)
                                                   : Qt.rgba(0.5, 0.5, 0.5, 0.15)
                                    radius: 4
                                    implicitWidth: _lt.implicitWidth + 12
                                    implicitHeight: _lt.implicitHeight + 8
                                    border.color: tracked ? "transparent"
                                                          : Qt.rgba(0.5, 0.5, 0.5, 0.3)
                                    border.width: 1

                                    StyledText {
                                        id: _lt
                                        anchors.centerIn: parent
                                        text: parent.lineName
                                        color: parent.tracked ? "white" : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: picker.toggleLine(
                                            _searchResult.stationData, parent.lineName)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: picker.searchText.length >= 2 && picker.filteredStations.length === 0
                width: pickerCol.width
                text: "No stations found"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                visible: picker.searchText.length < 2 && picker.allStations.length > 0
                    && picker.selectedStations.length === 0
                width: pickerCol.width
                text: "Type at least 2 characters to search " + picker.allStations.length + " stations"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
