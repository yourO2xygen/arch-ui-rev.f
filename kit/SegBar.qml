// ARCH·UI v2 — kit/SegBar.qml (DESIGN REV.E .tscal / GRID-A6: терминальная
// шкала-сетка — линейка прибора: сегменты-тики, каждый majorEvery-й выше,
// активная часть — ИНВЕРСИЕЙ, граница резкая, без градиентов)
//
// Геометрия из макета (.mbar .tscal): высота 8 (мажорный тик), сегмент 4,
// gap 2; 20 сегментов, мажорные — (index+1) % majorEvery === 0, т.е. при 20
// сегментах тики на 50% и 100% (макетный JS: j%10===9). Неактивные сегменты —
// ghost-контуры rgba(255,255,255,.09) (Theme.raise2); заполненные — инверсные
// Theme.txt. Ghost-датчик (iGPU / нет gpu) — заполненные tx2 с opacity .35,
// как .mcell.ghost .tscal i.f в макете.
//
// Сегменты растягиваются по ширине (flex:1 в макете; width задаёт потребитель),
// число фиксировано (segments) — это приборка, а не ёлка: lit считается из
// анимируемого value, каждый сегмент переключается цветом разом и мгновенно.
// Значение приезжает Behavior-ом на value (может отключиться у потребителя).
//
// Использование:
//   import "../kit"
//   SegBar { width: parent.width; value: SysMon.cpu }
//   SegBar { width: parent.width; value: SysMon.gpu; ghost: true }

import QtQuick
import ".."

Item {
    id: root

    property real value: 0            // 0..1
    property bool ghost: false        // ghost-датчик: заполненные — txt2 · .35
    property int segments: 20         // ~20 тиков-сегментов (макет s-01 «20-seg»)
    property int majorEvery: 10       // каждый majorEvery-й сегмент — мажорный тик

    // Высоты/gap — Theme-производные из .mbar .tscal (база: сегмент 4, мажор 8, gap 2)
    readonly property int segH: Theme.f(4)
    readonly property int majH: Theme.f(8)
    readonly property int tickGap: Theme.f(2)

    readonly property int count: Math.max(1, root.segments)
    // макетный JS: on = j < Math.round(f/5) при 20 сегментах ⇔ round(value·count)
    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * count)
    // сегменты растянуты в ширину целиком (flex:1); субпиксельная разбивка
    // не дрейфует, т.к. x считается от той же segW
    readonly property real segW: (width - (count - 1) * tickGap) / count

    implicitWidth: 228
    implicitHeight: majH
    // plain Item в Column имеет height 0 — геометрия Column'ы ненадёжна без явного
    // биндинга (урок ревью T5; штрихи были видны только потому, что нет clip)
    height: implicitHeight

    Behavior on value {
        NumberAnimation {
            duration: Motion.hoverMs
            easing.type: Easing.Bezier
            easing.bezierCurve: Motion.apple
        }
    }

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            readonly property bool major:
                (index + 1) % root.majorEvery === 0
            x: index * (root.segW + root.tickGap)
            anchors.bottom: parent.bottom        // align-items:flex-end в макете
            width: root.segW
            height: major ? root.majH : root.segH
            // инверсная заливка активной доли; ghost-вариант — как в макете
            color: index < root.lit
                   ? (root.ghost ? Theme.txt2 : Theme.txt)
                   : Theme.raise2
            opacity: root.ghost && index < root.lit ? 0.35 : 1
        }
    }
}
