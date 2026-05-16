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
    property var todayDay: null
    property string totalContributions: "0"
    property bool isError: false
    property bool isLoading: false
    property string errorMessage: ""
    property var lastRefreshTime: null
    property bool isManualRefresh: false

    Component.onCompleted: {
        initializePlaceholders()
    }

    onCodeforcesHandleChanged: checkAndStartTimer()
    onRefreshIntervalChanged: {
        if (refreshTimer.running) {
            refreshTimer.restart()
        }
    }

    function checkAndStartTimer() {
        if (codeforcesHandle) {
            if (!refreshTimer.running) {
                refreshTimer.start()
            }
        } else {
            refreshTimer.stop()
            initializePlaceholders()
        }
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
        todayDay = placeholders[placeholders.length - 1]

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

    function escapeShellString(str) {
        if (!str) return ""
        return str.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\$/g, "\\$").replace(/`/g, "\\`")
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval * 1000
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: {
            if (root.codeforcesHandle) {
                root.isManualRefresh = false
                root.refreshHeatmap()
            } else {
                root.isError = true
                root.errorMessage = "Configure Codeforces handle in settings"
            }
        }
    }

    function refreshHeatmap() {
        if (!codeforcesHandle) {
            isError = true
            errorMessage = "Configure Codeforces handle in settings"
            return
        }

        const now = Date.now()
        if (lastRefreshTime && (now - lastRefreshTime) < 30000) {
            return
        }

        lastRefreshTime = now
        isLoading = true
        codeforcesProcess.running = true
    }

    function buildScript() {
        const escapedHandle = escapeShellString(codeforcesHandle)

        return `
CODEFORCES_HANDLE="${escapedHandle}"
    COLOR_0="#1b1f2a"
    COLOR_1="#263b6d"
    COLOR_2="#1d6f6b"
    COLOR_3="#1f8a4c"
    COLOR_4="#b59b17"
    COLOR_5="#d97706"
    COLOR_6="#dc2626"

color_for_count() {
    count="$1"
    if [ "$count" -le 0 ]; then echo "$COLOR_0"
    elif [ "$count" -eq 1 ]; then echo "$COLOR_1"
    elif [ "$count" -le 2 ]; then echo "$COLOR_2"
    elif [ "$count" -le 4 ]; then echo "$COLOR_3"
    elif [ "$count" -le 7 ]; then echo "$COLOR_4"
    elif [ "$count" -le 11 ]; then echo "$COLOR_5"
    else echo "$COLOR_6"
    fi
}

today=$(date +%Y-%m-%d)
today_timestamp=$(date -d "$today" +%s)
today_dow=$(date -d "$today" +%u)
if [ "$today_dow" = "7" ]; then
    current_sunday="$today"
else
    current_sunday=$(date -d "$today -$today_dow days" +%Y-%m-%d)
fi
start_date=$(date -d "$current_sunday -49 days" +%Y-%m-%d)
start_timestamp=$(date -d "$start_date" +%s)

url="https://codeforces.com/api/user.status?handle=$CODEFORCES_HANDLE&from=1&count=1000"
temp_response=$(mktemp)
http_code=$(curl -s -w "%{http_code}" -o "$temp_response" "$url")
body=$(cat "$temp_response")
rm -f "$temp_response"

if [ "$http_code" != "200" ]; then
    jq -n --arg msg "Codeforces API error (HTTP $http_code)" '{contributions:[],gridData:[],total:0,error:true,errorMessage:$msg}'
    exit 1
fi

status=$(echo "$body" | jq -r '.status // "FAILED"')
if [ "$status" != "OK" ]; then
    comment=$(echo "$body" | jq -r '.comment // "Unknown Codeforces API error"')
    jq -n --arg msg "$comment" '{contributions:[],gridData:[],total:0,error:true,errorMessage:$msg}'
    exit 1
fi

declare -A daily_counts
total_submissions=0
while read -r submission_json; do
    [ -z "$submission_json" ] && continue
    verdict=$(echo "$submission_json" | jq -r '.verdict // ""')
    [ "$verdict" != "OK" ] && continue
    creation_time=$(echo "$submission_json" | jq -r '.creationTimeSeconds // 0')
    [ "$creation_time" -lt "$start_timestamp" ] && continue
    [ "$creation_time" -gt "$today_timestamp" ] && continue
    submission_date=$(date -d "@$creation_time" +%Y-%m-%d)
    daily_counts["$submission_date"]=$(( \${daily_counts["$submission_date"]:-0} + 1 ))
    total_submissions=$((total_submissions + 1))
done < <(echo "$body" | jq -c '.result[]')

weekday_names=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
all_days=()
grid_json="["
current_week="["
week_day_count=0
first_week=1
current_timestamp=$(date -d "$start_date" +%s)
while [ "$current_timestamp" -le "$today_timestamp" ]; do
    current_date=$(date -d "@$current_timestamp" +%Y-%m-%d)
    weekday=$(date -d "@$current_timestamp" +%w)
    weekday_name="\${weekday_names[$weekday]}"
    formatted_date=$(date -d "@$current_timestamp" "+%d / %b / %y")
    count=\${daily_counts["$current_date"]:-0}
    color=$(color_for_count "$count")
    day_obj=$(jq -nc --argjson weekday "$weekday" --arg weekdayName "$weekday_name" --arg date "$formatted_date" --argjson count "$count" --arg color "$color" '{weekday:$weekday,weekdayName:$weekdayName,date:$date,count:$count,color:$color}')
    all_days+=("$day_obj")
    [ "$week_day_count" -gt 0 ] && current_week="$current_week,"
    current_week="$current_week$day_obj"
    week_day_count=$((week_day_count + 1))
    if [ "$week_day_count" -eq 7 ]; then
        current_week="$current_week]"
        if [ "$first_week" -eq 1 ]; then grid_json="$grid_json$current_week"; first_week=0; else grid_json="$grid_json,$current_week"; fi
        current_week="["
        week_day_count=0
    fi
    current_timestamp=$((current_timestamp + 86400))
done

if [ "$week_day_count" -gt 0 ]; then
    while [ "$week_day_count" -lt 7 ]; do
        placeholder_weekday=$week_day_count
        placeholder_name="\${weekday_names[$placeholder_weekday]}"
        placeholder_obj=$(jq -nc --argjson weekday "$placeholder_weekday" --arg weekdayName "$placeholder_name" --arg date "--/--" --argjson count 0 --arg color "$COLOR_0" '{weekday:$weekday,weekdayName:$weekdayName,date:$date,count:$count,color:$color}')
        [ "$week_day_count" -gt 0 ] && current_week="$current_week,"
        current_week="$current_week$placeholder_obj"
        week_day_count=$((week_day_count + 1))
    done
    current_week="$current_week]"
    if [ "$first_week" -eq 1 ]; then grid_json="$grid_json$current_week"; else grid_json="$grid_json,$current_week"; fi
fi

grid_json="$grid_json]"
day_count=\${#all_days[@]}
pill_start=$((day_count - 7))
[ "$pill_start" -lt 0 ] && pill_start=0
pill_json="["
pill_count=0
for (( i=pill_start; i<day_count; i++ )); do
    [ "$pill_count" -gt 0 ] && pill_json="$pill_json,"
    pill_json="$pill_json\${all_days[$i]}"
    pill_count=$((pill_count + 1))
done
pill_json="$pill_json]"

printf '{"contributions":%s,"gridData":%s,"total":%d,"error":false}\n' "$pill_json" "$grid_json" "$total_submissions"
exit 0
`
    }

    Process {
        id: codeforcesProcess
        command: ["/usr/bin/env", "bash", "-c", buildScript()]
        running: false

        stdout: SplitParser {
            onRead: function(data) {
                try {
                    const result = JSON.parse(data.trim())
                    if (result.error) {
                        root.isError = true
                        root.errorMessage = result.errorMessage || "Unknown error"
                        root.initializePlaceholders()
                        root.isLoading = false
                        if (root.isManualRefresh) notifyFail.running = true
                        return
                    }

                    root.isError = false
                    root.isLoading = false

                    let newContributions = result.contributions || []
                    while (newContributions.length < 7) {
                        newContributions.push({ weekday: "---", date: "--/--", count: 0, color: Theme.surfaceContainer })
                    }
                    root.contributions = newContributions.slice(0, 7)
                    root.totalContributions = result.total.toString()

                    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let newGridData = result.gridData || []
                    while (newGridData.length < 8) {
                        const emptyWeek = []
                        for (let d = 0; d < 7; d++) {
                            emptyWeek.push({ weekday: d, weekdayName: days[d], date: "--/--", count: 0, color: Theme.surfaceContainer })
                        }
                        newGridData.unshift(emptyWeek)
                    }
                    for (let w = 0; w < newGridData.length; w++) {
                        while (newGridData[w].length < 7) {
                            const missingDay = newGridData[w].length
                            newGridData[w].push({ weekday: missingDay, weekdayName: days[missingDay], date: "--/--", count: 0, color: Theme.surfaceContainer })
                        }
                    }
                    root.gridData = newGridData.slice(-8)
                    if (root.gridData.length > 0) {
                        const lastWeek = root.gridData[root.gridData.length - 1]
                        root.todayDay = lastWeek[lastWeek.length - 1]
                    }
                    if (root.isManualRefresh) notifySuccess.running = true
                } catch (e) {
                    root.isError = true
                    root.errorMessage = "Failed to parse Codeforces response"
                    root.initializePlaceholders()
                    root.isLoading = false
                }
            }
        }

        onExited: function(exitCode, exitStatus) {
            root.isLoading = false
            if (exitCode !== 0 && !root.isError) {
                root.isError = true
                root.errorMessage = "Script failed with exit code: " + exitCode
                if (root.isManualRefresh) notifyFail.running = true
            }
        }
    }

    Process {
        id: notifySuccess
        command: ["notify-send", "-t", "3000", "Codeforces Synced", "Submissions refreshed successfully"]
        running: false
    }

    Process {
        id: notifyFail
        command: ["notify-send", "-u", "critical", "-t", "5000", "Codeforces Sync Failed", root.errorMessage]
        running: false
    }

    Process {
        id: openProfileProcess
        command: ["xdg-open", "https://codeforces.com/profile/" + root.codeforcesHandle]
        running: false
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
                    color: index < root.contributions.length ? root.contributions[index].color : Theme.surfaceContainer
                    border.color: Qt.darker(color, 1.2)
                    border.width: 1
                    opacity: root.isLoading ? 0.6 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 300 } }
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
                    color: index < root.contributions.length ? root.contributions[index].color : Theme.surfaceContainer
                    border.color: Qt.darker(color, 1.2)
                    border.width: 1
                    opacity: root.isLoading ? 0.6 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }
        }
    }

    property int popoutX: (pluginData && pluginData.popoutX) ? pluginData.popoutX : -1
    property int popoutY: (pluginData && pluginData.popoutY) ? pluginData.popoutY : -1

    popoutContent: Component {
        PopoutComponent {
            id: popout
            x: root.popoutX >= 0 ? root.popoutX : x
            y: root.popoutY >= 0 ? root.popoutY : y
            onXChanged: if (visible) PluginService.savePluginData("codeforcesHeatmap", "popoutX", x)
            onYChanged: if (visible) PluginService.savePluginData("codeforcesHeatmap", "popoutY", y)
            headerText: "Codeforces Heatmap"
            detailsText: {
                if (root.isError) return root.errorMessage
                if (root.isLoading) return "Loading..."
                return root.codeforcesHandle
            }
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    height: 84
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: Theme.primary
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#2563eb" }
                                GradientStop { position: 1.0; color: "#1f8a4c" }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: "CF"
                                color: "white"
                                font.weight: Font.Bold
                                font.pixelSize: 18
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: root.codeforcesHandle || "Set your handle"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: root.isError ? root.errorMessage : (root.totalContributions + " contributions")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacingS

                    Rectangle {
                        width: Theme.iconSize * 1.5
                        height: Theme.iconSize * 1.5
                        radius: Theme.iconSize * 0.75
                        color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        DankIcon { anchors.centerIn: parent; name: root.iconRefresh; size: Theme.iconSize * 0.8; color: refreshArea.containsMouse ? Theme.primary : Theme.surfaceText }
                        MouseArea { id: refreshArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.isManualRefresh = true; root.refreshHeatmap() } }
                    }

                    Rectangle {
                        width: Theme.iconSize * 1.5
                        height: Theme.iconSize * 1.5
                        radius: Theme.iconSize * 0.75
                        color: openArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        DankIcon { anchors.centerIn: parent; name: root.iconOpen; size: Theme.iconSize * 0.8; color: openArea.containsMouse ? Theme.primary : Theme.surfaceText }
                        MouseArea { id: openArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.codeforcesHandle) openProfileProcess.running = true } }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }

                StyledRect {
                    visible: root.isError
                    width: parent.width
                    height: 100
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS
                        DankIcon { name: root.iconError; color: Theme.error; size: Theme.iconSize * 1.5; anchors.horizontalCenter: parent.horizontalCenter }
                        StyledText { text: "Failed to load submissions"; color: Theme.error; font.pixelSize: Theme.fontSizeSmall; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }

                Row {
                    visible: !root.isError
                    spacing: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    Column {
                        spacing: 3
                        topPadding: 2
                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            StyledText { text: modelData; font.pixelSize: 10; color: Theme.surfaceVariantText; width: 14; height: 26; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    Row {
                        spacing: 3
                        Repeater {
                            model: root.gridData
                            Column {
                                spacing: 3
                                property var weekData: modelData
                                Repeater {
                                    model: weekData
                                    Rectangle {
                                        property var dayData: modelData
                                        width: 26
                                        height: 26
                                        radius: 4
                                        color: dayData.color || Theme.surfaceContainer
                                        border.color: Qt.darker(color, 1.15)
                                        border.width: 1
                                        opacity: root.isLoading ? 0.6 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                        MouseArea { id: cellMouse; anchors.fill: parent; hoverEnabled: true }
                                        Rectangle {
                                            visible: cellMouse.containsMouse && dayData.date !== "--/--"
                                            x: -25
                                            y: -30
                                            width: tooltipText.implicitWidth + 12
                                            height: tooltipText.implicitHeight + 8
                                            color: Theme.surfaceContainerHighest
                                            radius: 4
                                            z: 100
                                            StyledText { id: tooltipText; anchors.centerIn: parent; text: dayData.date + ": " + dayData.count; font.pixelSize: 11; color: Theme.surfaceText }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: 96
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        Column {
                            width: 92
                            spacing: 2

                            StyledText {
                                text: root.todayDay ? root.todayDay.count : 0
                                color: Theme.primary
                                font.pixelSize: 42
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: "today"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Rectangle {
                            width: 1
                            height: parent.height - Theme.spacingL * 2
                            color: Theme.outlineVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            StyledText {
                                text: root.todayDay ? root.todayDay.weekdayName : "Today"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: root.todayDay ? root.todayDay.date : "--/--"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
