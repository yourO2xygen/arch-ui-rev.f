// ARCH·UI v2 — components/TaskMgr.qml (SPEC §4, DESIGN §4 «taskmgr», ANALYSIS §5)
// Панель процессов (слот A, panelId "taskmgr"): фильтр h34 (простой TextInput —
// kit/Field придёт в T7) + чип сортировки cpu/mem/pid; таблица: pid / name / cpu /
// mem / user / kill, строки h30, hover — raise, hot-cpu (≥20%) — жирный белый;
// kill-кнопка появляется на hover строки, её ховер — инверсия. Клик — SIGTERM
// (ProcMon.kill), строка гаснет фейдом Motion.killFade и удаляется следующим тиком
// ps (подтверждение исчезновением). Head/foot живут в shell.qml.
//
// Использование (shell.qml): body: Component { … } — panelId назначает kit/Panel.qml.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    readonly property int rowH: 30
    readonly property int colPid: 44
    readonly property int colCpu: 56
    readonly property int colMem: 64
    readonly property int colUser: 88
    readonly property int colKill: 34
    readonly property real colName: width - colPid - colCpu - colMem - colUser - colKill

    // ------------------------------------------------------- фильтр + сортировка
    Row {
        id: toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        // Поле: h34, фон raise2, каретка «_» 8×2 (Motion.caretBlink). kit/Field — T7.
        Rectangle {
            id: field
            width: parent.width - sortChip.width - parent.spacing
            height: 34
            color: Theme.raise2
            border.width: filterInput.activeFocus ? 1 : 0
            border.color: Theme.dim

            TextInput {
                id: filterInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.txt
                selectionColor: Theme.raise2
                selectedTextColor: Theme.txt
                clip: true
                font.family: Theme.font
                font.pixelSize: 11
                onTextChanged: ProcMon.filter = text

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filterInput.text.length === 0
                             && !filterInput.activeFocus
                    text: "filter…"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11
                }

                // каретка-подчёркивание (ANALYSIS: 8×2, blink + пауза)
                cursorDelegate: Rectangle {
                    width: 8
                    height: 2
                    color: Theme.txt
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: filterInput.activeFocus
                        NumberAnimation { duration: Motion.caretBlink / 2; to: 0 }
                        NumberAnimation { duration: Motion.caretBlink / 2; to: 1 }
                    }
                }
            }
        }

        Kit.Chip {
            id: sortChip
            anchors.verticalCenter: parent.verticalCenter
            text: "sort " + ProcMon.sortBy
            onClicked: ProcMon.sortBy = ProcMon.sortBy === "cpu" ? "mem"
                     : ProcMon.sortBy === "mem" ? "pid" : "cpu"
        }
    }

    // ------------------------------------------------------------------ шапка
    Row {
        id: header
        anchors.top: toolbar.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 18

        Repeater {
            model: [
                { t: "pid", w: root.colPid },
                { t: "name", w: root.colName },
                { t: "cpu", w: root.colCpu },
                { t: "mem", w: root.colMem },
                { t: "user", w: root.colUser },
                { t: "", w: root.colKill }
            ]

            delegate: Text {
                required property var modelData
                width: modelData.w
                height: parent.height
                text: modelData.t.toUpperCase()
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9
                font.letterSpacing: 1
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: modelData.t === "cpu" || modelData.t === "mem"
                                     ? Text.AlignRight : Text.AlignLeft
                rightPadding: modelData.t === "mem" ? 8 : 0
                leftPadding: modelData.t === "user" ? 8 : 0
            }
        }
    }

    // ---------------------------------------------------------------- таблица
    Flickable {
        anchors.top: header.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentHeight: rowsCol.height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: rowsCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right

            Repeater {
                model: ProcMon.model

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    readonly property var rec: modelData
                    readonly property bool hot: rec.cpu >= 20
                    readonly property bool hovered: ma.containsMouse && !rec.killing

                    width: parent.width
                    height: root.rowH
                    color: hovered ? Theme.raise : "transparent"
                    // kill-фейд 400ms; удалит строку следующий тик ps
                    opacity: rec.killing ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.killFade
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.apple
                        }
                    }

                    Row {
                        anchors.fill: parent

                        Text {
                            width: root.colPid
                            height: root.rowH
                            text: row.rec.pid
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: root.colName
                            height: root.rowH
                            text: row.rec.name
                            color: Theme.txt2
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: root.colCpu
                            height: root.rowH
                            text: row.rec.cpu.toFixed(1)
                            color: row.hot ? Theme.txt : Theme.txt2
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: row.hot ? Font.Bold : Font.Normal
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: root.colMem
                            height: root.rowH
                            text: SysMon.fmtKb(row.rec.rss)
                            color: Theme.txt2
                            font.family: Theme.font
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            rightPadding: 8
                        }
                        Text {
                            width: root.colUser
                            height: root.rowH
                            text: row.rec.user
                            color: Theme.txt2
                            leftPadding: 8
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 10
                            verticalAlignment: Text.AlignVCenter
                        }
                        Item {
                            width: root.colKill
                            height: root.rowH

                            // kill-кнопка: видна на hover строки, её ховер — инверсия
                            Rectangle {
                                id: killBtn
                                anchors.centerIn: parent
                                width: 30
                                height: 18
                                visible: row.hovered
                                color: killMa.containsMouse ? Theme.invBg : Theme.raise2

                                Text {
                                    anchors.centerIn: parent
                                    text: "kill"
                                    color: killMa.containsMouse ? Theme.invFg : Theme.txt2
                                    font.family: Theme.font
                                    font.pixelSize: 9
                                }
                                MouseArea {
                                    id: killMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ProcMon.kill(row.rec.pid)
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        // hover-детект; клики уходят в kill-кнопку
                    }
                }
            }
        }
    }
}
