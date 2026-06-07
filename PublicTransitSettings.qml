import QtQuick
import QtQuick.Controls
import "data/stations.js" as StationsData
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wienerLinien"

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
        text: "Tracked Stations"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        text: "Search for a station and click it to add. Click a tracked station to remove it."
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
        property var selectedStations: []

        property var filteredStations: {
            const q = picker.searchText.toLowerCase().trim()
            if (q.length < 2) return []
            return picker.allStations.filter(function(s) {
                return s.name.toLowerCase().indexOf(q) !== -1
            }).slice(0, 12)
        }

        // Called by PluginSettings automatically when pluginService is ready or data changes
        function loadValue() {
            try {
                picker.selectedStations = JSON.parse(root.loadValue("trackedStopsJson", "[]"))
            } catch (e) {
                picker.selectedStations = []
            }
        }

        function isSelected(stationName) {
            for (let i = 0; i < picker.selectedStations.length; i++) {
                if (picker.selectedStations[i].name === stationName) return true
            }
            return false
        }

        function addStation(station) {
            if (picker.isSelected(station.name)) return
            const next = picker.selectedStations.concat([{
                name: station.name,
                stopIds: station.stopIds,
                lines: station.lines || []
            }])
            picker.selectedStations = next
            root.saveValue("trackedStopsJson", JSON.stringify(next))
        }

        function removeStation(name) {
            const next = picker.selectedStations.filter(function(s) {
                return s.name !== name
            })
            picker.selectedStations = next
            root.saveValue("trackedStopsJson", JSON.stringify(next))
        }

        Component.onCompleted: {
            picker.allStations = StationsData.stations
            picker.loadValue()
        }

        Column {
            id: pickerCol
            width: parent.width
            spacing: Theme.spacingXS

            // ---- Selected stations ----
            Repeater {
                model: picker.selectedStations
                delegate: Rectangle {
                    required property var modelData
                    width: pickerCol.width
                    height: 40
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    StyledText {
                        id: _selName
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: _removeBtn.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: _removeBtn
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 14
                        color: _removeMouse.containsMouse
                            ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                            : "transparent"

                        DankIcon {
                            name: "close"
                            size: 14
                            color: Theme.error
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: _removeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.removeStation(modelData.name)
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
                        onTextChanged: picker.searchText = text
                    }
                }
            }

            // ---- Search results ----
            Repeater {
                model: picker.filteredStations
                delegate: Rectangle {
                    id: _result
                    required property var modelData
                    readonly property bool selected: picker.isSelected(modelData.name)

                    width: pickerCol.width
                    height: _resContent.implicitHeight + Theme.spacingXS * 2
                    radius: Theme.cornerRadius
                    color: _result.selected
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        : (_resMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : "transparent")

                    Row {
                        id: _resContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        DankIcon {
                            visible: _result.selected
                            name: "check_circle"
                            size: 14
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.name
                            color: _result.selected ? Theme.primary : Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: (modelData.lines || []).slice(0, 6).join(", ")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall - 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: _resMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: _result.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (!_result.selected)
                                picker.addStation(modelData)
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
