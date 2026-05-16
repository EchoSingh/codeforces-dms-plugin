import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "codeforcesHeatmap"

    PluginGlobalVar {
        id: handleSetting
        varName: "handle"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: refreshIntervalSetting
        varName: "refreshInterval"
        defaultValue: 300
    }

    Component.onCompleted: {
        const savedHandle = PluginService.loadPluginData("codeforcesHeatmap", "handle", "")
        const savedInterval = PluginService.loadPluginData("codeforcesHeatmap", "refreshInterval", 300)

        console.log("Codeforces Heatmap: Settings loaded from disk")

        if (savedHandle) {
            handleField.text = savedHandle
            PluginService.setGlobalVar("codeforcesHeatmap", "handle", savedHandle)
        }

        intervalField.text = savedInterval.toString()
        PluginService.setGlobalVar("codeforcesHeatmap", "refreshInterval", savedInterval)
    }

    Column {
        width: parent.width
        spacing: Theme.spacingL

        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Codeforces Heatmap Settings"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                text: "Display your daily Codeforces problem solving activity in your status bar"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        StyledRect {
            width: parent.width
            height: handleColumn.implicitHeight + Theme.spacingL * 2
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius

            Column {
                id: handleColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "person"
                        size: Theme.iconSize
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Codeforces Handle"
                        font.weight: Font.Bold
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                DankTextField {
                    id: handleField
                    width: parent.width - Theme.spacingL * 2
                    placeholderText: "tourist"
                    text: ""
                }

                StyledText {
                    text: "Your Codeforces handle (public profile)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        StyledRect {
            width: parent.width
            height: intervalColumn.implicitHeight + Theme.spacingL * 2
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius

            Column {
                id: intervalColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "schedule"
                        size: Theme.iconSize
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Refresh Interval"
                        font.weight: Font.Bold
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                DankTextField {
                    id: intervalField
                    width: parent.width - Theme.spacingL * 2
                    placeholderText: "300"
                    text: "300"
                    validator: IntValidator { bottom: 60 }
                }

                StyledText {
                    text: "Refresh interval in seconds (minimum: 60)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }

        DankButton {
            width: parent.width
            text: "Save Settings"
            iconName: "check"

            onClicked: {
                if (!handleField.text.trim()) {
                    ToastService.showError("Codeforces handle is required")
                    return
                }

                var interval = parseInt(intervalField.text) || 300
                if (interval < 60) {
                    ToastService.showError("Refresh interval must be at least 60 seconds")
                    return
                }

                PluginService.savePluginData("codeforcesHeatmap", "handle", handleField.text.trim())
                PluginService.savePluginData("codeforcesHeatmap", "refreshInterval", interval)

                PluginService.setGlobalVar("codeforcesHeatmap", "handle", handleField.text.trim())
                PluginService.setGlobalVar("codeforcesHeatmap", "refreshInterval", interval)

                console.log("Codeforces Heatmap: Settings saved - handle:", handleField.text.trim())

                ToastService.showSuccess("Settings saved successfully!")
            }
        }
    }
}
