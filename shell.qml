//@ pragma AppId archui
// ARCH·UI v2 — точка входа (SPEC §1/§2/§7).
// Окна: 3 колонки-слота (A/B/C) + calendar + bar + toasts — все создаются один раз и
// живут всегда (демон), exclusionMode: Ignore, namespace "archui:*", маска ввода пустая
// на закрытых слотах. IPC-таргет "archui", GlobalShortcut лаунчера (обработчик запуска —
// задача 7). Сетка — логические px, scale 1.2 (экран 1600×900).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "kit"

ShellRoot {
    id: root

    Component.onCompleted: console.info(
        `[archui] shell loaded · screen ${Quickshell.screens[0].name} ` +
        `${Quickshell.screens[0].width}x${Quickshell.screens[0].height} ` +
        `@${Quickshell.screens[0].scale}`)

    // --------------------------------------------------------------- СЛОТ A
    Panel {
        id: colA
        slot: "A"
        panels: ["docker", "taskmgr"]
        WlrLayershell.namespace: "archui:col-a"
        anchors { left: true; top: true }
        margins.left: 24
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colA.panelId === "" ? "SLOT A" : colA.panelId.toUpperCase()
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
            }
        }
        body: Component { Placeholder {} }
        foot: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "archui"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "slot a"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
            }
        }
    }

    // --------------------------------------------------------------- СЛОТ B
    Panel {
        id: colB
        slot: "B"
        panels: ["launcher", "logout", "sysinfo"]
        WlrLayershell.namespace: "archui:col-b"
        anchors { left: true; top: true }
        margins.left: 548
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colB.panelId === "" ? "SLOT B" : colB.panelId.toUpperCase()
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
            }
        }
        body: Component { Placeholder {} }
        foot: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "archui"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "slot b"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
            }
        }
    }

    // --------------------------------------------------------------- СЛОТ C
    Panel {
        id: colC
        slot: "C"
        panels: ["chat", "aimgr", "notifcenter"]
        WlrLayershell.namespace: "archui:col-c"
        anchors { left: true; top: true }
        margins.left: 1072
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colC.panelId === "" ? "SLOT C" : colC.panelId.toUpperCase()
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
            }
        }
        body: Component { Placeholder {} }
        foot: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "archui"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "slot c"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
            }
        }
    }

    // ------------------------------------------------------------- CALENDAR
    // Персистентен по требованию пользователя (SPEC §2); режимы idle-dim/чип — задача 3.
    PanelWindow {
        id: calendar
        WlrLayershell.namespace: "archui:calendar"
        anchors { left: true; top: true }
        margins.left: 24
        margins.top: 24
        implicitWidth: 264
        implicitHeight: 288
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { width: calendar.width; height: calendar.height }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 0

            Text {
                anchors.centerIn: parent
                text: "CALENDAR"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }
    }

    // ------------------------------------------------------------------ BAR
    // Транзиент 2.8s — задача 3; сейчас — IPC-тоггл. ~500×44 top-center.
    PanelWindow {
        id: bar
        WlrLayershell.namespace: "archui:bar"
        anchors { left: true; top: true }
        margins.top: 0
        margins.left: Math.round(((bar.screen ? bar.screen.width : 1600) - bar.implicitWidth) / 2)
        implicitWidth: 500
        implicitHeight: 44
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: LayoutState.slots.bar !== null
        mask: Region { width: bar.width; height: bar.height }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 0

            Text {
                anchors.centerIn: parent
                text: "BAR"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }
    }

    // --------------------------------------------------------------- TOASTS
    // Пустой хост стека тостов (задача 3): тостов нет → маска пустая, ввод насквозь.
    PanelWindow {
        id: toasts
        WlrLayershell.namespace: "archui:toasts"
        anchors { right: true; top: true }
        margins.right: 24
        margins.top: 24
        implicitWidth: 276
        implicitHeight: 300
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: true
        mask: Region { width: 0; height: 0 }
    }

    // ------------------------------------------------------------------- IPC
    IpcHandler {
        target: "archui"

        function toggle(panelId: string): void { LayoutState.toggle(panelId) }
        function toggleBar(): void { LayoutState.toggleBar() }
        function dismissToasts(): void { LayoutState.dismissToasts() }
        function dnd(on: bool): void { LayoutState.setDnd(on) }
    }

    // Реакция на хоткей — задача 7 (обработчик запуска лаунчера); бинд в hyprland.conf:
    //   bind = SUPER, R, global, archui:launcher
    GlobalShortcut {
        appid: "archui"
        name: "launcher"
        description: "Open the app launcher (slot B)"

        onPressed: LayoutState.toggle("launcher")
    }
}
