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

        Qt.callLater(function() {
            if (codeforcesHandle) {
                refreshTimer.start()
            }
        })
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
        return str.replace(/\\/g, "\\\\")
                  .replace(/"/g, "\\\"")
                  .replace(/\$/g, "\\$")
                  .replace(/`/g, "\\`")
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
            console.log("Codeforces: Skipping refresh (cooldown active)")
            return
        }

        console.log("Codeforces: Fetching submissions for", codeforcesHandle)
        lastRefreshTime = now
        isLoading = true
        codeforcesProcess.running = true
    }

    function buildScript() {
        const escapedHandle = escapeShellString(codeforcesHandle)

        return `
# Codeforces Heatmap Fetcher (Bash + Public API)
CODEFORCES_HANDLE="${escapedHandle}"

COLOR_0="#1f2430"
COLOR_1="#2563eb"
COLOR_2="#8b5cf6"
COLOR_3="#ec4899"
COLOR_4="#f59e0b"
COLOR_5="#ef4444"

color_for_count() {
    count="$1"
    if [ "$count" -le 0 ]; then
        echo "$COLOR_0"
    elif [ "$count" -eq 1 ]; then
        echo "$COLOR_1"
    elif [ "$count" -le 3 ]; then
        echo "$COLOR_2"
    elif [ "$count" -le 6 ]; then
        echo "$COLOR_3"
    elif [ "$count" -le 10 ]; then
        echo "$COLOR_4"
    else
        echo "$COLOR_5"
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

page=1
page_size=1000

declare -A daily_counts

while true; do
    url="https://codeforces.com/api/user.status?handle=$CODEFORCES_HANDLE&from=$page&count=$page_size"

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

    result_count=$(echo "$body" | jq '.result | length')
    if [ "$result_count" -eq 0 ]; then
        break
    fi

    while read -r submission_json; do
        if [ -z "$submission_json" ]; then
            continue
        fi

        verdict=$(echo "$submission_json" | jq -r '.verdict // ""')
        if [ "$verdict" != "OK" ]; then
            continue
        fi

        creation_time=$(echo "$submission_json" | jq -r '.creationTimeSeconds // 0')
        if [ "$creation_time" -lt "$start_timestamp" ] || [ "$creation_time" -gt "$today_timestamp" ]; then
            continue
        fi

        submission_date=$(date -d "@$creation_time" +%Y-%m-%d)
        daily_counts["$submission_date"]=$(( ${daily_counts["$submission_date"]:-0} + 1 ))
    done < <(echo "$body" | jq -c '.result[]')

    oldest_time=$(echo "$body" | jq -r '.result[-1].creationTimeSeconds // 0')
    if [ "$oldest_time" -lt "$start_timestamp" ] || [ "$result_count" -lt "$page_size" ]; then
        break
    fi

    page=$((page + page_size))
    sleep 2
done

current_timestamp=$(date -d "$start_date" +%s)
end_timestamp=$today_timestamp

weekday_names=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
all_days=()
grid_json="["
current_week="["
week_day_count=0
first_week=1

total_submissions=0

while [ "$current_timestamp" -le "$end_timestamp" ]; do
    current_date=$(date -d "@$current_timestamp" +%Y-%m-%d)
    weekday=$(date -d "@$current_timestamp" +%w)
    weekday_name="\${weekday_names[$weekday]}"
    formatted_date=$(date -d "@$current_timestamp" +%m/%d)
    count=${daily_counts["$current_date"]:-0}
    color=$(color_for_count "$count")

    total_submissions=$((total_submissions + count))

    day_obj=$(jq -nc --argjson weekday "$weekday" --arg weekdayName "$weekday_name" --arg date "$formatted_date" --argjson count "$count" --arg color "$color" '{weekday:$weekday,weekdayName:$weekdayName,date:$date,count:$count,color:$color}')
    all_days+=("$day_obj")

    if [ "$week_day_count" -eq 0 ]; then
        current_week="["
    else
        current_week="$current_week,"
    fi
    current_week="$current_week$day_obj"

    week_day_count=$((week_day_count + 1))
    if [ "$week_day_count" -eq 7 ]; then
        current_week="$current_week]"
        if [ "$first_week" -eq 1 ]; then
            grid_json="$grid_json$current_week"
            first_week=0
        else
            grid_json="$grid_json,$current_week"
        fi
        current_week="["
        week_day_count=0
    fi

    current_timestamp=$((current_timestamp + 86400))
done

if [ "$week_day_count" -gt 0 ]; then
    while [ "$week_day_count" -lt 7 ]; do
        placeholder_weekday=$week_day_count
        placeholder_name="\${weekday_names[$placeholder_weekday]}"
        placeholder_date="--/--"
        placeholder_color="$COLOR_0"
        placeholder_obj=$(jq -nc --argjson weekday "$placeholder_weekday" --arg weekdayName "$placeholder_name" --arg date "$placeholder_date" --argjson count 0 --arg color "$placeholder_color" '{weekday:$weekday,weekdayName:$weekdayName,date:$date,count:$count,color:$color}')
        if [ "$week_day_count" -eq 0 ]; then
            current_week="[$placeholder_obj"
        else
            current_week="$current_week,$placeholder_obj"
        fi
        week_day_count=$((week_day_count + 1))
    done
    current_week="$current_week]"
    if [ "$first_week" -eq 1 ]; then
        grid_json="$grid_json$current_week"
    else
        grid_json="$grid_json,$current_week"
    fi
fi

grid_json="$grid_json]"

day_count=\${#all_days[@]}
pill_start=$((day_count - 7))
if [ "$pill_start" -lt 0 ]; then
    pill_start=0
fi

pill_json="["
pill_count=0

for (( i=pill_start; i<day_count; i++ )); do
    if [ "$pill_count" -gt 0 ]; then
        pill_json="$pill_json,"
    fi
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
            onRead: data => {
                try {
                    const result = JSON.parse(data.trim())

                    if (result.error) {
                        console.error("Codeforces: API error -", result.errorMessage)
                        root.isError = true
                        root.errorMessage = result.errorMessage || "Unknown error"
                        root.initializePlaceholders()
                        root.isLoading = false
                        if (root.isManualRefresh) {
                            notifyFail.running = true
                        }
                        return
                    }

                    root.isError = false
                    root.isLoading = false

                    let newContributions = result.contributions || []
                    while (newContributions.length < 7) {
                        newContributions.push({
                            weekday: "---",
                            date: "--/--",
                            count: 0,
                            color: Theme.surfaceContainer
                        })
                    }
                    newContributions = newContributions.slice(0, 7)

                    root.contributions = newContributions
                    root.totalContributions = result.total.toString()

                    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let newGridData = result.gridData || []

                    while (newGridData.length < 8) {
                        const emptyWeek = []
                        for (let d = 0; d < 7; d++) {
                            emptyWeek.push({
                                weekday: d,
                                weekdayName: days[d],
                                date: "--/--",
                                count: 0,
                                color: Theme.surfaceContainer
                            })
                        }
                        newGridData.unshift(emptyWeek)
                    }

                    for (let w = 0; w < newGridData.length; w++) {
                        while (newGridData[w].length < 7) {
                            const missingDay = newGridData[w].length
                            newGridData[w].push({
                                weekday: missingDay,
                                weekdayName: days[missingDay],
                                date: "--/--",
                                count: 0,
                                color: Theme.surfaceContainer
                            })
                        }
                    }

                    newGridData = newGridData.slice(-8)
                    root.gridData = newGridData

                    if (root.isManualRefresh) {
                        notifySuccess.running = true
                    }
                } catch (e) {
                    console.error("Codeforces: Failed to parse response -", e, "Data:", data)
                    root.isError = true
                    root.errorMessage = "Failed to parse Codeforces response"
                    root.initializePlaceholders()
                    root.isLoading = false
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            if (exitCode !== 0 && !root.isError) {
                console.error("Codeforces: Script failed with exit code", exitCode)
                root.isError = true
                root.errorMessage = "Script failed with exit code: " + exitCode
                if (root.isManualRefresh) {
                    notifyFail.running = true
                }
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
                    color: index < root.contributions.length
                           ? root.contributions[index].color
                           : Theme.surfaceContainer
                    border.color: Qt.darker(color, 1.2)
                    border.width: 1
                    opacity: root.isLoading ? 0.6 : 1.0

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
                    opacity: root.isLoading ? 0.6 : 1.0

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

    function savePopoutPosition(x, y) {
        PluginService.savePluginData("codeforcesHeatmap", "popoutX", x)
        PluginService.savePluginData("codeforcesHeatmap", "popoutY", y)
        PluginService.setGlobalVar("codeforcesHeatmap", "popoutX", x)
        PluginService.setGlobalVar("codeforcesHeatmap", "popoutY", y)
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            x: root.popoutX >= 0 ? root.popoutX : x
            y: root.popoutY >= 0 ? root.popoutY : y

            onXChanged: if (visible) Qt.callLater(() => root.savePopoutPosition(x, y))
            onYChanged: if (visible) Qt.callLater(() => root.savePopoutPosition(x, y))

            headerText: "Codeforces Activity"
            detailsText: {
                if (root.isError) return root.errorMessage
                if (root.isLoading) return "Loading..."
                return root.totalContributions + " solved problems (8 weeks)"
            }
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacingS

                    Rectangle {
                        width: Theme.iconSize * 1.5
                        height: Theme.iconSize * 1.5
                        radius: Theme.iconSize * 0.75
                        color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        DankIcon {
                            anchors.centerIn: parent
                            name: root.iconRefresh
                            size: Theme.iconSize * 0.8
                            color: refreshArea.containsMouse ? Theme.primary : Theme.surfaceText

                            NumberAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: root.isLoading
                            }
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.isManualRefresh = true
                                root.refreshHeatmap()
                            }
                        }
                    }

                    Rectangle {
                        width: Theme.iconSize * 1.5
                        height: Theme.iconSize * 1.5
                        radius: Theme.iconSize * 0.75
                        color: openArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        DankIcon {
                            anchors.centerIn: parent
                            name: root.iconOpen
                            size: Theme.iconSize * 0.8
                            color: openArea.containsMouse ? Theme.primary : Theme.surfaceText
                        }

                        MouseArea {
                            id: openArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.codeforcesHandle) {
                                    openProfileProcess.running = true
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineVariant
                }

                StyledRect {
                    visible: root.isError
                    width: parent.width
                    height: 100
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.iconError
                            color: Theme.error
                            size: Theme.iconSize * 1.5
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "Failed to load submissions"
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
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

                            StyledText {
                                text: modelData
                                font.pixelSize: 10
                                color: Theme.surfaceVariantText
                                width: 14
                                height: 26
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Row {
                        spacing: 3

                        Repeater {
                            model: root.gridData

                            Column {
                                spacing: 3
                                required property var modelData
                                required property int index

                                Repeater {
                                    model: modelData

                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 4
                                        color: modelData.color || Theme.surfaceContainer
                                        border.color: Qt.darker(color, 1.15)
                                        border.width: 1

                                        required property var modelData

                                        opacity: root.isLoading ? 0.6 : 1.0

                                        Behavior on opacity {
                                            NumberAnimation { duration: 200 }
                                        }

                                        Behavior on color {
                                            ColorAnimation { duration: 300 }
                                        }

                                        MouseArea {
                                            id: cellMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }

                                        Rectangle {
                                            visible: cellMouse.containsMouse && modelData.date !== "--/--"
                                            x: -25
                                            y: -30
                                            width: tooltipText.implicitWidth + 12
                                            height: tooltipText.implicitHeight + 8
                                            color: Theme.surfaceContainerHighest
                                            radius: 4
                                            z: 100

                                            StyledText {
                                                id: tooltipText
                                                anchors.centerIn: parent
                                                text: modelData.date + ": " + modelData.count
                                                font.pixelSize: 11
                                                color: Theme.surfaceText
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    visible: !root.isError && root.totalContributions === "0"
                    width: parent.width
                    height: 50
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    StyledText {
                        anchors.centerIn: parent
                        text: "No solved problems yet"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }
}
