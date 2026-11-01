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

    // Ghost-эхо панели (SPEC §3): +40/+140, scale .99→.952, opacity .45→0, длительность 620
    // (ANALYSIS §3.2: `animation: ghost .62s var(--apple)`; DESIGN-RESEARCH называет 380 —
    // взят факт из CSS макета); на replace отключено. ghostOpacityTo всегда 0 — отдельно
    // не токенизируется.
    readonly property int ghostDelay1: 40
    readonly property int ghostDelay2: 140
    readonly property int ghostFade: 620
    readonly property real ghostScaleFrom: 0.99
    readonly property real ghostScaleTo: 0.952
    readonly property real ghostOpacityFrom: 0.45

    // Пульс точки статуса: 2s InOutSine, только у filled-варианта
    readonly property int dotPulse: 2000

    // Замена панели: старая уходит 180 (fade + scale .97, без ghost-эхо);
    // новая стартует на +120 (SPEC §2)
    readonly property int replaceExit: 180
    readonly property int replaceStagger: 120

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

    // Бар/календарь (T3): полумиг табло часов (провал и возврат — по половине),
    // свёртывание окна календаря, фейд nav-строки и прочего скрываемого контента,
    // idle-dim календаря до 0.55
    readonly property int clockFlicker: 30
    readonly property int calendarCollapse: 260
    readonly property int navFade: 160
    readonly property int idleDimFade: 300
}
