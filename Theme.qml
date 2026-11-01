pragma Singleton
// ARCH·UI v2 — единственное место цветов/шрифтов/размеров (SPEC §3).
// Значения переписаны дословно из SPEC §3 / Global Constraints — не редактировать локально в компонентах.

import QtQuick
import Quickshell

Singleton {
    id: root

    // --- Цвета (SPEC §3) ---
    readonly property color surface: "#000000"
    readonly property color txt: "#f4f4f5"
    readonly property color txt2: "#a1a1aa"
    readonly property color dim: "#56565e"
    readonly property color ghost: "#3f3f46"
    readonly property color raise: Qt.rgba(1, 1, 1, 0.05)  // rgba(255,255,255,.05)
    readonly property color raise2: Qt.rgba(1, 1, 1, 0.09) // rgba(255,255,255,.09)
    readonly property color invBg: "#f4f4f5"
    readonly property color invFg: "#000000"

    // Effective stroke иконок: stroke_vb = strokeE * 24 / size, пол 1.25 (см. kit/Icon.qml)
    readonly property real strokeE: 1.5

    // --- Шрифты ---
    // JetBrainsMono NFM — системный (400–700), FontLoader не нужен.
    readonly property string font: "JetBrainsMono NFM"
    // DSEG7 — FontLoader из assets; фактическое имя семейства берётся из загруженного шрифта.
    readonly property string fontDseg: dseg.name

    FontLoader {
        id: dseg
        source: Qt.resolvedUrl("assets/fonts/DSEG7Classic-Bold.ttf")
    }

    // --- Отступы: фактические значения макета (SPEC §3: 6/8/10/11/12/13/18) ---
    readonly property int s6: 6
    readonly property int s8: 8
    readonly property int s10: 10
    readonly property int s11: 11
    readonly property int s12: 12
    readonly property int s13: 13
    readonly property int s18: 18

    // --- Стекло (SPEC §9): false не создаёт текстуры стекла вообще ---
    readonly property bool glass: false
}
