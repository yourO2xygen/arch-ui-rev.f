pragma Singleton
// ARCH·UI v2 — единственное место цветов/шрифтов/размеров (SPEC §3).
// Значения переписаны дословно из SPEC §3 / Global Constraints — не редактировать локально в компонентах.

import QtQuick
import Quickshell
import Quickshell.Hyprland

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
    readonly property color ghostLine: Qt.rgba(1, 1, 1, 0.5) // ghost-контуры анимаций (ANALYSIS §3.2)

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

    // --- px-множитель (Task 17): расчёт от фактического экрана ---
    // Базовый дизайн отрисован под 1600×900 при monitor scale 1.2. Layershell-окна
    // Hyprland НЕ автомасштабирует (surface px = логические px экрана), поэтому
    // соответствие «шрифты панели крупнее так же, как терминал» даём множителем:
    //   px = screenScale / designScale   (scale 1.25 → px ≈ 1.042)
    // px умножает ДИЗАЙНОВЫЕ шрифты/высоты (fs*/h*/wLabel); позиции окон при этом
    // считаются от фактического логического экрана в shell.qml (не через px).
    // Источник scale — монитор Hyprland того же экрана, к которому аттачатся окна
    // (Quickshell.screens[0].scale в этой сборке не заполнен — undefined),
    // фолбэк — designScale (px=1, базовая сетка).
    readonly property real designScale: 1.2
    readonly property real px: Hyprland.monitors.length > 0 && Hyprland.monitors[0].scale > 0
                              ? Hyprland.monitors[0].scale / designScale : 1
    function f(base: real): int { return Math.round(base * root.px) }

    // --- Отступы: фактические значения макета (SPEC §3: 6/8/10/11/12/13/18) ---
    readonly property int s6: 6
    readonly property int s8: 8
    readonly property int s10: 10
    readonly property int s11: 11
    readonly property int s12: 12
    readonly property int s13: 13
    readonly property int s18: 18

    // --- Шрифты: pixelSize для font.* (базовые значения × px) ---
    readonly property int fs8: f(8)
    readonly property int fs9: f(9)
    readonly property int fs10: f(10)
    readonly property int fs11: f(11)
    readonly property int fs12: f(12)
    readonly property int fs13: f(13)
    readonly property int fs15: f(15)
    readonly property int fs18: f(18)

    // --- Структурные высоты: head/foot панелей, ряды, чипы (базовые × px) ---
    readonly property int hHead: f(40)   // head-кит слота (kit/Panel)
    readonly property int hFoot: f(30)   // foot-кит слота (kit/Panel)
    readonly property int hRow: f(30)    // панельные ряды (TaskMgr/AgentMgr/AgentChat/Docker info)
    readonly property int hRowL: f(34)   // крупные ряды (Launcher)
    readonly property int hRowS: f(28)   // компактные ряды (kit/Row, строки SysInfo hw)
    readonly property int hChip: f(22)   // чипы/мини-плитки

    // --- Отступы (дополнение к 6/8/10…): паддинги панелей/чипов ---
    readonly property int s16: 16

    // --- Ключевые ширины (базовая × px: шрифт метки растёт вместе с колонкой) ---
    readonly property int wLabel: f(84)  // метка-колонка label caps (Docker/SysInfo)

    // --- Радиусы ---
    readonly property int r2: 2

    // --- Стекло (SPEC §9): false не создаёт текстуры стекла вообще ---
    readonly property bool glass: false

    // --- Глич-шейдер появления панелей (Task 9, SPEC §8): kill-критерий как у стекла —
    // если шейдер дороже ~2ms/кадр на этой машине — false отключает шейдер целиком
    // (остаётся lite-вариант без GPU), текстуры при false не создаются
    readonly property bool glitch: true
}
