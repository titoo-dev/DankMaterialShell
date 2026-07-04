import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Calendar detail view (drill-down, island-styled). macOS menu-bar-clock vibe:
// month grid + per-day event dots + the selected day's agenda (via CalendarService,
// which uses `khal`; degrades gracefully to an empty agenda when khal is absent).
Column {
    id: calCol
    property var island: null
    // shown month + selected day, as plain ints (avoids date-binding churn)
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()      // 0-11
    property int selYear: new Date().getFullYear()
    property int selMonth: new Date().getMonth()
    property int selDay: new Date().getDate()
    // JS weekday (0=Sun..6=Sat) the user's locale starts its week on
    readonly property int firstDowJs: Qt.locale().firstDayOfWeek % 7
    // dependency handle forcing event lookups to re-read after CalendarService
    // updates — the service REASSIGNS eventsByDate wholesale, so binding the
    // object identity is exact (a key count would miss same-size updates)
    readonly property var eventsRev: CalendarService.eventsByDate

    function todayDate() { return new Date() }
    function cellDate(i) {
        const first = new Date(viewYear, viewMonth, 1)
        const offset = (first.getDay() - firstDowJs + 7) % 7   // locale-first column offset
        return new Date(viewYear, viewMonth, 1 - offset + i)
    }
    function sameYMD(d, y, m, day) { return d.getFullYear() === y && d.getMonth() === m && d.getDate() === day }
    function loadVisible() { CalendarService.loadEvents(cellDate(0), cellDate(41)) }
    function shiftMonth(delta) {
        let m = viewMonth + delta, y = viewYear
        if (m < 0) { m = 11; y-- } else if (m > 11) { m = 0; y++ }
        viewMonth = m; viewYear = y
        loadVisible()
    }
    function reset() {
        const now = todayDate()
        viewYear = now.getFullYear(); viewMonth = now.getMonth()
        selYear = now.getFullYear(); selMonth = now.getMonth(); selDay = now.getDate()
        CalendarService.loadCurrentMonth()
    }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "calendar" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) reset()
    // lazily loaded: the panel is born visible, so onVisibleChanged never fires
    Component.onCompleted: if (visible) reset()
    transform: Translate { x: island.panelView === "calendar" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // header: back · title · today
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: cBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: cBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: cBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: cBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText {
            anchors.left: cBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Calendar"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        }
        Rectangle {  // jump back to today
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: todayLbl.implicitWidth + Theme.spacingM; height: 28; radius: 14
            color: todayArea.containsMouse ? Theme.primary : Theme.surfaceLight
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            StyledText { id: todayLbl; anchors.centerIn: parent; text: I18n.tr("Today"); font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; color: todayArea.containsMouse ? Theme.primaryText : island.subText }
            MouseArea { id: todayArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calCol.reset() }
        }
    }

    // month nav: ‹  Month Year  ›
    Item {
        width: parent.width; height: 30
        Rectangle {
            id: prevBtn
            width: 28; height: 28; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: prevArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: prevArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 18; color: island.subText }
            MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calCol.shiftMonth(-1) }
        }
        StyledText {
            anchors.centerIn: parent
            text: Qt.formatDate(new Date(calCol.viewYear, calCol.viewMonth, 1), "MMMM yyyy")
            color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        }
        Rectangle {
            id: nextBtn
            width: 28; height: 28; radius: width / 2
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            color: nextArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: nextArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_right"; size: 18; color: island.subText }
            MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calCol.shiftMonth(1) }
        }
    }

    // weekday header (localized names AND first day of week)
    Row {
        width: parent.width
        Repeater {
            model: 7
            Item {
                width: parent.width / 7; height: 18
                StyledText {
                    anchors.centerIn: parent
                    text: { const js = (calCol.firstDowJs + index) % 7; return Qt.locale().dayName(js === 0 ? 7 : js, Locale.ShortFormat) }
                    color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true
                }
            }
        }
    }

    // 6-week day grid
    Grid {
        width: parent.width
        columns: 7
        readonly property real cell: width / 7
        Repeater {
            model: 42
            Item {
                width: parent.cell; height: parent.cell
                readonly property var d: calCol.cellDate(index)
                readonly property bool inMonth: d.getMonth() === calCol.viewMonth
                readonly property bool isToday: { island.clockShort; const t = calCol.todayDate(); return calCol.sameYMD(d, t.getFullYear(), t.getMonth(), t.getDate()) }   // clockShort dep → re-evaluates past midnight
                readonly property bool isSel: calCol.sameYMD(d, calCol.selYear, calCol.selMonth, calCol.selDay)
                readonly property bool hasEv: { calCol.eventsRev; return CalendarService.hasEventsForDate(d) }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 4; height: parent.height - 4; radius: width / 2
                    color: parent.isToday && !parent.isSel ? Theme.primarySelected : (dayArea.containsMouse ? Theme.surfaceHover : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    Rectangle {  // selection: accent disc behind the day number
                        visible: parent.parent.isSel
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: width / 2
                        color: Theme.primary
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: parent.parent.d.getDate()
                        color: parent.parent.isSel ? Theme.primaryText : (parent.parent.inMonth ? island.textColor : island.subText)
                        opacity: parent.parent.inMonth ? 1 : 0.45
                        font.pixelSize: Theme.fontSizeSmall; font.bold: parent.parent.isToday || parent.parent.isSel
                    }
                }
                Rectangle {  // event dot
                    visible: parent.hasEv
                    width: 4; height: 4; radius: 2
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    color: island.accent
                }
                MouseArea {
                    id: dayArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { calCol.selYear = parent.d.getFullYear(); calCol.selMonth = parent.d.getMonth(); calCol.selDay = parent.d.getDate() }
                }
            }
        }
    }

    // agenda for the selected day
    Flickable {
        width: parent.width; height: Math.min(agenda.height, 132); clip: true
        contentHeight: agenda.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: agenda
            width: parent.width; spacing: 3
            readonly property var items: { calCol.eventsRev; return CalendarService.getEventsForDate(new Date(calCol.selYear, calCol.selMonth, calCol.selDay)) }
            StyledText {
                width: parent.width; height: 34
                visible: agenda.items.length === 0
                text: I18n.tr("No events"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: agenda.items
                Rectangle {
                    width: agenda.width; height: 40; radius: 10
                    color: Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.5)
                    Rectangle {  // accent rail
                        width: 3; radius: 1.5; color: island.accent
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingS
                        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 8; anchors.bottomMargin: 8
                    }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM + 4
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: modelData.title || I18n.tr("Untitled"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        }
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: modelData.allDay ? I18n.tr("All day") : (Qt.formatTime(modelData.start, "HH:mm") + (modelData.location ? ("  ·  " + modelData.location) : ""))
                            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }
                }
            }
        }
    }
}
