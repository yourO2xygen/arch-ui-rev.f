// ARCH·UI v2 — kit/Dot.qml (ANALYSIS §7.7)
// Точка состояния 7×7 radius 50%: on — txt + pulse 2s (Motion.dotPulse, только filled),
// idle — ghost, off — полая (inset-тень макета → кольцо 1px dim).
//
// Использование:
//   import "../kit"   // (или import "../kit" as Kit — рядом с QtQuick.Row)
//   Dot { state: "on" }   // "on" | "idle" | "off"

import QtQuick
import ".."

Rectangle {
    id: root

    property string state: "on"   // "on" | "idle" | "off"

    width: 7
    height: 7
    radius: 3.5
    color: root.state === "on" ? Theme.txt
         : root.state === "idle" ? Theme.ghost
         : "transparent"
    border.width: root.state === "off" ? 1 : 0
    border.color: Theme.dim

    SequentialAnimation on opacity {
        running: root.state === "on"
        loops: Animation.Infinite
        NumberAnimation { duration: Motion.dotPulse / 2; to: 1; easing.type: Easing.InOutSine }
        NumberAnimation { duration: Motion.dotPulse / 2; to: 0.4; easing.type: Easing.InOutSine }
    }
}
