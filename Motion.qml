pragma Singleton
// ARCH·UI v2 — единственное место движения (SPEC §3).
// Длительности в мс. apple — базовая кривая BezierCurve(.25,.1,.25,1).

import QtQuick
import Quickshell

Singleton {
    id: root

    // Базовая кривая. Использование в анимации:
    //   NumberAnimation { duration: Motion.panelOpen
    //                     easing.type: Easing.Bezier
    //                     easing.bezierCurve: Motion.apple }
    // (последние две единицы — контрольная точка 1,1, требование Qt для BezierSpline)
    readonly property list<real> apple: [0.25, 0.1, 0.25, 1, 1, 1]

    // Панель: открытие 420 → контент на 430-й мс, фейд контента 220 (SPEC §2/§3)
    readonly property int panelOpen: 420
    readonly property int contentDelay: 430
    readonly property int contentFade: 220

    // Замена панели: старая уходит 180 (fade + scale .97, без ghost-эхо)
    readonly property int replaceExit: 180

    // Глич: 350 (панели) / 200 (тосты/бар)
    readonly property int glitchPanel: 350
    readonly property int glitchLite: 200

    // Прочее (SPEC §3)
    readonly property int hoverMs: 120
    readonly property int killFade: 400
    readonly property int dndToggle: 160
    readonly property int launcherGrow: 260
    readonly property int barTimeout: 2800
    readonly property int caretBlink: 1070
    readonly property int caretPause: 900
}
