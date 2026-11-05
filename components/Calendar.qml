// ARCH·UI v2 — components/Calendar.qml (SPEC §2, ANALYSIS §5.4, DESIGN-RESEARCH §4.2/§4.4)
// Дата-first иерархия REV.D-F (макет 2026-11-05): counter-номер дня 40px tabular
// («05») + подпись «THURSDAY / november 2026 · week 45» — на месте бывших часов.
// Контент окна archui:calendar 264×288 (в свернутом виде окно — 264×40):
//   head 28 (y10)  — ‹ месяц ›  + дата-чип (клик — сворачивание/разворачивание)
//   date 48 (y40)  — counter дня + день недели caps / месяц год · ISO-неделя
//   dow  16 (y92)  — MO…SU,caps dim, старт недели — понедельник
//   grid 154 (y112) — 42 ячейки 24px, gap 2; сегодня — инверсия, соседи — ghost
//   foot 16 (y270) — iso-8601 слева | год·месяц сетки справа (ghost)
//
// Данные — реальный месяц JS Date; номер недели — ISO-8601 (в макете формула была
// упрощённой — SPEC это чинит). ‹ › двигают отображаемый месяц (не персистится).
//
// Поведение: без ввода 30s → dim opacity .55 (Behavior 300ms); клик по дате-чипу —
// сворачивание до чипа 264×40 (только дата+месяц) и обратно; живое состояние,
// reload его не сохраняет.
//
// Использование (shell.qml):
//   PanelWindow { implicitHeight: cal.collapsed ? 40 : 288; Calendar { id: cal; anchors.fill: parent } }

import QtQuick
import Quickshell
import ".."
import "../kit" as Kit
import "datefmt.js" as DateFmt

Item {
    id: root

    // ------------------------------------------------------------------ состояние
    property bool collapsed: false   // живое — НЕ персистится
    property bool dimmed: false      // idle >30s

    // ------------------------------------------------------------- геометрия
    readonly property int padH: 14   // 264 − 2·14 − 12(gap) = 7·32 — сетка ровно 236
    readonly property int headH: 28
    readonly property int dowH: 16
    readonly property int cellH: 24  // REV.D-F: 6·24+5·2=154 — освобождает место date-band

    // -------------------------------------------------------------------- время
    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property int todayY: parseInt(Qt.formatDateTime(clock.date, "yyyy"))
    readonly property int todayM: parseInt(Qt.formatDateTime(clock.date, "M")) - 1
    readonly property int todayD: parseInt(Qt.formatDateTime(clock.date, "d"))
    readonly property var today: new Date(todayY, todayM, todayD)

    // --------------------------------------------------------- отображаемый месяц
    property int viewYear: todayY
    property int viewMonth: todayM   // 0-based

    function shiftMonth(delta) {
        const d = new Date(root.viewYear, root.viewMonth + delta, 1)
        root.viewYear = d.getFullYear()
        root.viewMonth = d.getMonth()
    }

    readonly property string monthLabel: DateFmt.monthTitle(viewYear, viewMonth)

    // 42 ячейки: старт с понедельника (lead = (getDay()+6)%7), соседи помечены out
    readonly property var cells: {
        const out = []
        const first = new Date(root.viewYear, root.viewMonth, 1)
        const lead = (first.getDay() + 6) % 7
        const start = new Date(root.viewYear, root.viewMonth, 1 - lead)
        for (let i = 0; i < 42; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            out.push({ day: d.getDate(), out: d.getMonth() !== root.viewMonth, t: d.getTime() })
        }
        return out
    }

    // ------------------------------------------------------------ ISO-8601 неделя
    function isoWeek(d) {
        const dt = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const dayNum = dt.getUTCDay() || 7          // вс → 7
        dt.setUTCDate(dt.getUTCDate() + 4 - dayNum) // четверг текущей недели
        const yearStart = new Date(Date.UTC(dt.getUTCFullYear(), 0, 1))
        return Math.ceil(((dt - yearStart) / 86400000 + 1) / 7)
    }

    readonly property int weekNo: isoWeek(today)

    // ------------------------------------------------------------------ поведение
    opacity: root.dimmed ? 0.55 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.idleDimFade
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.apple
        }
    }

    Timer { id: idleTimer; interval: 30000; onTriggered: root.dimmed = true }

    function poke() {
        root.dimmed = false
        idleTimer.restart()
    }

    // Фоновый ввод (поля между ячейками/чипом) — только hover-детект, клики вниз.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.poke()
        onContainsMouseChanged: if (containsMouse) root.poke()
    }

    // ------------------------------------------------- скрываемый контент календаря
    // Один контейнер с общим фейдом (Motion.navFade): в свернутом виде остаётся
    // только чип (он — сиблинг ниже). По-элементные opacity убраны — фейд симметричен.
    Item {
        id: expanded
        anchors.fill: parent
        opacity: root.collapsed ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.navFade
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }

        // ------------------------------------------------------------------ head
        Item {
            id: head
            x: root.padH
            y: 10
            width: parent.width - root.padH * 2
            height: root.headH

            Rectangle {
                id: prevBtn
                width: Theme.hChip
                height: Theme.hChip
                anchors.verticalCenter: parent.verticalCenter
                color: prevMa.containsMouse || prevMa.pressed ? Theme.raise2 : Theme.raise
                Kit.Icon { name: "chevron-left"; size: 13; color: Theme.txt2; anchors.centerIn: parent }
                MouseArea {
                    id: prevMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.shiftMonth(-1); root.poke() }
                    onPositionChanged: root.poke()
                    onContainsMouseChanged: if (containsMouse) root.poke()
                }
            }

            Text {
                id: monthText
                anchors.left: prevBtn.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.monthLabel
                color: Theme.txt
                font.family: Theme.font
                font.pixelSize: Theme.fs12
                font.weight: Font.DemiBold
            }

            Rectangle {
                id: nextBtn
                width: Theme.hChip
                height: Theme.hChip
                anchors.left: monthText.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                color: nextMa.containsMouse || nextMa.pressed ? Theme.raise2 : Theme.raise
                Kit.Icon { name: "chevron-right"; size: 13; color: Theme.txt2; anchors.centerIn: parent }
                MouseArea {
                    id: nextMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.shiftMonth(1); root.poke() }
                    onPositionChanged: root.poke()
                    onContainsMouseChanged: if (containsMouse) root.poke()
                }
            }
        }

        // --------------------------------------------------------------- date-band
        // REV.D-F: counter-номер дня 40px tabular занимает место бывших часов +
        // подпись: день недели caps / месяц год · ISO-неделя.
        Item {
            id: dateBand
            x: root.padH
            y: 40
            width: parent.width - root.padH * 2
            height: 48

            Text {
                id: dayCounter
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                text: DateFmt.dateCounter(root.todayD)
                color: Theme.txt
                font.family: Theme.font
                font.pixelSize: 40
                font.weight: Font.Bold
                font.letterSpacing: -0.8          // ls -.02em от 40px
                font.features: { "tnum": true }    // tabular-nums (макет .n)
            }

            Column {
                anchors.left: dayCounter.right
                anchors.leftMargin: 12            // gap:12 как в макете
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                spacing: 5

                Text {
                    text: DateFmt.weekdayFullCaps(root.today)   // THURSDAY
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: Theme.fs10
                    font.weight: Font.Medium
                    font.letterSpacing: 1.2
                }

                Text {
                    // ноябрь отображаемой сетки + ISO-неделя сегодня
                    text: DateFmt.monthWeekFull(root.viewYear, root.viewMonth, root.weekNo)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                    font.letterSpacing: 0.5
                }
            }
        }

        // ------------------------------------------------------------------- dow
        Grid {
            id: dowRow
            x: root.padH
            y: 92
            columns: 7
            spacing: 2

            Repeater {
                model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

                delegate: Item {
                    required property string modelData
                    width: 32
                    height: root.dowH

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fs9
                        font.weight: Font.Medium
                        font.letterSpacing: 0.85   // ls .1em от 8.5px
                    }
                }
            }
        }

        // ------------------------------------------------------------------ grid
        Grid {
            id: grid
            x: root.padH
            y: 112
            columns: 7
            spacing: 2

            Repeater {
                model: root.cells

                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property bool isToday: modelData.t === root.today.getTime()

                    width: 32
                    height: root.cellH
                    color: isToday ? Theme.invBg
                         : hoverMa.containsMouse && !modelData.out ? Theme.raise : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.day
                        color: parent.isToday ? Theme.invFg
                             : parent.modelData.out ? Theme.ghost : Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.weight: parent.isToday ? Font.Bold : Font.Medium
                    }

                    MouseArea {
                        id: hoverMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onPositionChanged: root.poke()   // движение внутри ячейки тоже будит
                        onContainsMouseChanged: if (containsMouse) root.poke()
                    }
                }
            }
        }

        // ------------------------------------------------------------------ foot
        Item {
            x: root.padH
            y: 270
            width: parent.width - root.padH * 2
            height: 16

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "iso-8601"
                color: Theme.ghost
                font.family: Theme.font
                font.pixelSize: Theme.fs9
                font.letterSpacing: 1.2
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // 2026·11 — год·месяц отображаемой сетки (ghost)
                text: DateFmt.monthYearCompact(root.viewYear, root.viewMonth)
                color: Theme.ghost
                font.family: Theme.font
                font.pixelSize: Theme.fs9
            }
        }
    }

    // --------------------------------------------------------------- дата-чип
    // Вне expanded: единственное, что остаётся при свёртывании (264×40).
    // y = 10 (head) + (28 − 22)/2 — тот же вертикальный центр, что у head.
    Rectangle {
        id: chip
        anchors.right: parent.right
        anchors.rightMargin: root.padH
        y: 14
        width: chipText.implicitWidth + 16   // .chip{padding:4px 8px} → 8 с боков
        height: Theme.hChip
        color: chipMa.containsMouse || chipMa.pressed ? Theme.raise2 : Theme.raise

        Text {
            id: chipText
            anchors.centerIn: parent
            text: root.collapsed
                  ? DateFmt.chipFull(root.todayY, root.todayM, root.todayD)
                  : DateFmt.dayMonth(root.todayM, root.todayD)
            color: Theme.txt2
            font.family: Theme.font
            font.pixelSize: Theme.fs10
            font.weight: Font.Medium
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.collapsed = !root.collapsed; root.poke() }
            onPositionChanged: root.poke()
            onContainsMouseChanged: if (containsMouse) root.poke()
        }
    }

    Component.onCompleted: idleTimer.restart()
}
