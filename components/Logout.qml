// ARCH·UI v2 — components/Logout.qml (SPEC §4, DESIGN §4 «logout»)
// Сессия (слот B, panelId "logout"), компактная композиция Task 24: окно слота B
// стало маленьким (~241), поэтому плитки — квадраты Theme.hTile (~67×67·px) с fs11-
// подписями, 3+2 двумя рядами по центру body (без пустых 100-300px): lock / sleep /
// exit / reboot / power. Ховер — raise; power — ховер ИНВЕРСИЕЙ (максимум серьёзности).
// Клик:
//   lock    → /usr/bin/loginctl lock-session
//   sleep   → /usr/bin/systemctl suspend
//   exit    → /usr/bin/hyprctl dispatch exit   (сразу, без фейда — композитор умрёт)
//   reboot  → фейд-оверлей (Motion.haltFade) → /usr/bin/systemctl reboot
//   power   → фейд-оверлей (Motion.haltFade) → /usr/bin/systemctl poweroff
//   (абсолютные пути — SPEC §7: PATH демона ненадёжен)
// Подвал (head/foot в shell.qml): user · uptime.

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../kit" as Kit

Item {
    id: root

    readonly property int tileH: Theme.hTile
    readonly property int tileGap: Theme.s6

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
        // гейт на повторный тап/другую плитку, пока halt-фейд ещё идёт
        if (_pending.length > 0) return
        if (id === "reboot" || id === "power") {
            // короткий фейд «system halted» — экран всё равно уйдёт; оверлей на случай
            // медленного выключения (DESIGN §4). Отмена при replace панели во время
            // фейда — приемлема (юзер передумал): таймер умирает вместе с объектом.
            // КАНАЛ ЗАПУСКА — только таймер (SequentialAnimation.onStopped эмитится
            // и по stop() — немедленный poweroff минуя фейд).
            _pending = id
            halt.run(cmd)
            haltTimer.restart()
        } else {
            Quickshell.execDetached(cmd.split(" "))
        }
    }

    // Канал запуска halt-команды — ТОЛЬКО таймер (не animation.onStopped: stop()
    // эмитит stopped → немедленный poweroff минуя фейд + повтор).
    Timer {
        id: haltTimer
        interval: Motion.haltFade / 2
        onTriggered: {
            if (root._pending.length === 0) return
            const cmd = root._commandFor(root._pending)
            root._pending = ""
            if (cmd.length > 0) Quickshell.execDetached(cmd.split(" "))
            halt.fadeOut()   // панель возвращается, если сессия ещё жива (медленный shutdown / тест)
        }
    }

    HaltOverlay { id: halt }

    // --------------------------------------------------------------- плитки
    // 3+2 по центру: квадраты Theme.hTile, Row'ы центрированы по body (высота
    // контента 2×hTile+gap = 140 — та же цифра, что окно слота B в shell.qml).
    Column {
        anchors.centerIn: parent
        spacing: root.tileGap

        Repeater {
            // два ряда: [lock sleep exit] и [reboot power]
            model: [
                [
                    { id: "lock",   icon: "lock",     label: "LOCK" },
                    { id: "sleep",  icon: "moon",     label: "SLEEP" },
                    { id: "exit",   icon: "log-out",  label: "EXIT" }
                ],
                [
                    { id: "reboot", icon: "rotate-cw", label: "REBOOT" },
                    { id: "power",  icon: "power",    label: "POWER" }
                ]
            ]

            delegate: Row {
                id: tiles
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.tileGap

                Repeater {
                    model: tiles.modelData

                    delegate: Rectangle {
                        id: tile
                        required property var modelData

                        width: root.tileH
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
                                size: 16
                                color: tile.inverted ? Theme.invFg : Theme.txt2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.label
                                color: tile.inverted ? Theme.invFg : Theme.txt2
                                font.family: Theme.font
                                font.pixelSize: Theme.fs11
                                font.weight: Font.Medium
                                font.letterSpacing: 1
                            }
                        }

                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root._activate(tile.modelData.id) }
                    }
                }
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

        function run(cmd) {
            console.info("[archui] logout: halt overlay → " + cmd)
            haltIn.restart()
        }

        // Только визуальный фейд; запуск команды — haltTimer снаружи (I1).
        function fadeOut() {
            haltOut.restart()
        }

        SequentialAnimation {
            id: haltIn
            NumberAnimation {
                target: haltRect; property: "opacity"; to: 1; duration: Motion.haltFade / 2
            }
        }

        SequentialAnimation {
            id: haltOut
            NumberAnimation {
                target: haltRect; property: "opacity"; to: 0; duration: Motion.haltFade / 2
            }
        }

        Text {
            anchors.centerIn: parent
            text: "system halted"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fs11
            font.letterSpacing: 1
        }
    }


}
