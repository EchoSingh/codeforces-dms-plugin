import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 280
    popoutHeight: 340

    readonly property string iconRefresh: "refresh"
    readonly property string iconError: "error"
    readonly property string iconOpen: "open_in_browser"

    property string codeforcesHandle: (pluginData && pluginData.handle) ? pluginData.handle : ""
    property int refreshInterval: (pluginData && pluginData.refreshInterval) ? pluginData.refreshInterval : 300

    property var contributions: []
    property var gridData: []
    property string totalContributions: "0"
    property bool isError: false
    property bool isLoading: false
    property string errorMessage: ""
    property var lastRefreshTime: null
    property bool isManualRefresh: false

    Component.onCompleted: {
        initializePlaceholders()
    }

    function initializePlaceholders() {
        const placeholders = []
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        for (let i = 0; i < 7; i++) {
            placeholders.push({
                weekday: days[i],
                date: "--/--",
                count: 0,
                color: Theme.surfaceContainer
            })
        }

        contributions = placeholders
        totalContributions = "0"
        isError = false

        const gridPlaceholders = []
        for (let week = 0; week < 8; week++) {
            const weekData = []
            for (let day = 0; day < 7; day++) {
                weekData.push({
                    weekday: day,
                    weekdayName: days[day],
                    date: "--/--",
                    count: 0,
                    color: Theme.surfaceContainer
                })
            }
            gridPlaceholders.push(weekData)
        }
        gridData = gridPlaceholders
    }
    Timer {
        id: refreshTimer
        interval: root.refreshInterval * 1000
        repeat: true
        running: false
        triggeredOnStart: false
    }

    horizontalBarPill: Component {
        Row {
            spacing: 2

            Repeater {
                model: 7

                Rectangle {
                    width: 8
                    height: 16
                    radius: 2
                    color: index < root.contributions.length
                           ? root.contributions[index].color
                           : Theme.surfaceContainer
                    border.color: Qt.darker(color, 1.2)
                    border.width: 1
                    opacity: 1.0

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            Repeater {
                model: 7

                Rectangle {
                    width: 16
                    height: 8
                    radius: 2
                    color: index < root.contributions.length
                           ? root.contributions[index].color
                           : Theme.surfaceContainer
                    border.color: Qt.darker(color, 1.2)
                    border.width: 1
                    opacity: 1.0

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                }
            }
        }
    }

    property int popoutX: (pluginData && pluginData.popoutX) ? pluginData.popoutX : -1
    property int popoutY: (pluginData && pluginData.popoutY) ? pluginData.popoutY : -1

    popoutContent: Component {
        PopoutComponent {
            headerText: "Codeforces Activity"
            detailsText: "Ready"
            showCloseButton: false

            StyledText {
                text: "Codeforces Heatmap is installed"
                color: Theme.surfaceText
            }
        }
    }
}
