// ARCH·UI v2 — kit/SegBar.qml (ANALYSIS §3: полоса метрики — h 4, сегментированная,
// штрих 4 / промежуток 3, белая; заполнение от значения 0..1)
//
// Число штрихов считается из ширины (width задаёт потребитель); незаполненные штрихи —
// ghost. Литые штрихи не анимируются по одному — это приборка, а не ёлка: значение
// приезжает Behavior-ом на value (может отключиться у потребителя).
//
// Использование:
//   import "../kit"
//   SegBar { width: parent.width; value: SysMon.cpu }

import QtQuick
import ".."

Item {
    id: root

    property real value: 0            // 0..1
    readonly property int tickW: 4
    readonly property int tickGap: 3

    implicitWidth: 228
    implicitHeight: 4

    readonly property int tickCount:
        Math.max(1, Math.floor((width + tickGap) / (tickW + tickGap)))
    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * tickCount)

    Behavior on value {
        NumberAnimation {
            duration: Motion.hoverMs
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.apple
        }
    }

    Repeater {
        model: root.tickCount

        Rectangle {
            required property int index
            x: index * (root.tickW + root.tickGap)
            anchors.verticalCenter: parent.verticalCenter
            width: root.tickW
            height: 4
            color: index < root.lit ? Theme.txt : Theme.ghost
        }
    }
}
