// ARCH·UI v2 — components/Logout.qml (SPEC §4, DESIGN §4 «logout»)
// Сессия (слот B, panelId "logout"). 5 плиток h56 равной ширины: lock / sleep / exit /
// reboot / power. Ховер — raise; power — ховер ИНВЕРСИЕЙ (максимум серьёзности).
// Клик:
//   lock    → /usr/bin/loginctl lock-session
//   sleep   → /usr/bin/systemctl suspend
//   exit    → /usr/bin/hyprctl dispatch exit   (сразу, без фейда — композитор умрёт)
//   reboot  → фейд-оверлей (Motion.haltFade) → /usr/bin/systemctl reboot
//   power   → фейд-оверлей (Motion.haltFade) → /usr/bin/systemctl poweroff
//   (абсолютные пути — SPEC §7: PATH демона ненадёжен)
// Подвал (head/foot в shell.qml): user · uptime.

import QtQuick
import Quickshell.Io
import ".."
import "../kit" as Kit

Item {
    id: root

    readonly property int tileH: 56
    readonly property int tileGap: 6

    // Активная команда (для тестов: "what-command-would-run"); "" — ничего не ждёт
    readonly property string pendingCommand: _pending.length > 0 ? _commandFor(_pending) : ""
    property string _pending: ""

    function _commandFor(id) {
        switch (id) {
        case "lock":   return "/usr/bin/loginctl lock-session"
        case "sleep":  return "/usr/bin/systemctl suspend"
        case "exit":   return "/usr/bin/hyprctl dispatch exit"
        case "reboot": return "/usr/bin/systemctl reboot"
        case "power":  return "/usr/bin/systemctl poweroff"
        }
        return ""
    }

    function _activate(id) {
        const cmd = _commandFor(id)
        if (cmd.length === 0) return
        if (id === "reboot" || id === "power") {
            // короткий фейд «system halted» — экран всё равно уйдёт; оверлей на случай
            // медленного выключения (DESIGN §4)
            _pending = id
            halt.run(cmd)
        } else {
            Quickshell.execDetached(cmd)
        }
    }

    HaltOverlay { id: halt }

    // --------------------------------------------------------------- плитки
    Row {
        id: tiles
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.tileGap

        Repeater {
            model: [
                { id: "lock",   icon: "lock",     label: "LOCK" },
                { id: "sleep",  icon: "moon",     label: "SLEEP" },
                { id: "exit",   icon: "log-out",  label: "EXIT" },
                { id: "reboot", icon: "rotate-cw", label: "REBOOT" },
                { id: "power",  icon: "power",    label: "POWER" }
            ]

            delegate: Rectangle {
                id: tile
                required property var modelData

                width: (tiles.width - 4 * root.tileGap) / 5
                height: root.tileH
                border.width: 0

                // power — ховер-инверсия, остальные — raise → raise2
                readonly property bool inverted: tile.modelData.id === "power" && hover.hovered
                color: inverted ? Theme.invBg
                     : hover.hovered ? Theme.raise2
                     : Theme.raise

                Column {
                    anchors.centerIn: parent
                    spacing: 5

                    Kit.Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: tile.modelData.icon
                        size: 14
                        color: tile.inverted ? Theme.invFg : Theme.txt2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.label
                        color: tile.inverted ? Theme.invFg : Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 1
                    }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root._activate(tile.modelData.id) }
            }
        }
    }

    // Фейд-оверлей «system halted»: в пределах слота (не полноэкранный — окно слота B
    // живёт всегда, отдельное fullscreen-окно под разовый оверлей не создаём).
    component HaltOverlay: Rectangle {
        id: haltRect
        anchors.fill: parent
        color: Theme.surface
        opacity: 0
        visible: opacity > 0
        z: 10
        border.width: 0

        property string _cmd: ""

        function run(cmd) {
            console.info("[archui] logout: halt overlay → " + cmd)
            _cmd = cmd
            haltIn.restart()
        }

        SequentialAnimation {
            id: haltIn
            NumberAnimation {
                target: haltRect; property: "opacity"; to: 1; duration: Motion.haltFade / 2
            }
            onStopped: if (haltRect._cmd.length > 0) Quickshell.execDetached(haltRect._cmd)
        }

        Text {
            anchors.centerIn: parent
            text: "system halted"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11
            font.letterSpacing: 1
        }
    }
}
