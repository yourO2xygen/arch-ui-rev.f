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
    // Task 24 фикс: monitors.length не имеет change-notify — модель Hyprland
    // заполняется асинхронно ПОСЛЕ старта QML, биндинг замирал на px=1. Читаем
    // .values (список с notify) — px доедает до 1.04, когда monitors придут.
    readonly property real designScale: 1.2
    readonly property real px: {
        const ms = Hyprland.monitors.values
        return ms.length > 0 && ms[0].scale > 0 ? ms[0].scale / designScale : 1
    }
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
    // Task 24 (+25% контента, слоты A/C симметрично): эталон — терминал юзера 15px.
    // База fs-токенов поднята на один шаг (fs15/fs18 — уже ≈ эталон, не тронуты;
    // fs13 — только Placeholder, оставлен). Эффективные при px≈1.04:
    //   fs8=10 · fs9=11 · fs10=14 · fs11=15 · fs12=16 · fs15=16 · fs18=19
    readonly property int fs8: f(10)
    readonly property int fs9: f(11)
    readonly property int fs10: f(13)
    readonly property int fs11: f(14)
    readonly property int fs12: f(15)
    readonly property int fs13: f(13)
    readonly property int fs15: f(15)
    readonly property int fs18: f(18)

    // --- Структурные высоты: head/foot панелей, ряды, чипы (базовые × px) ---
    readonly property int hHead: f(40)   // head-кит слота (kit/Panel)
    readonly property int hFoot: f(30)   // foot-кит слота (kit/Panel)
    readonly property int hRow: f(30)    // панельные ряды (TaskMgr/Docker info)
    readonly property int hRowL: f(34)   // крупные ряды (Launcher)
    readonly property int hRowS: f(28)   // компактные ряды (kit/Row, строки SysInfo hw)
    readonly property int hChip: f(22)   // чипы/мини-плитки

    // --- Слот B: компактное окно (Task 24) ---
    // Все размеры — композиция токенов (никаких отдельных кусков вне Theme):
    //   лаунчер ст.1  = hDock (dock только)
    //   лаунчер ст.2  = hSlotB = dock + 4 строки списка (hRowL)
    //   logout        = hHead + padTop 12 + 2×hTile + s6 + padBottom 16 + hFoot
    //                   (паддинги 12/16 — литералы body kit/Panel.qml)
    readonly property int hDock: f(48)                       // dock лаунчера
    readonly property int hTile: f(64)                       // плитки logout (было 56 фикс)
    readonly property int hSlotB: hDock + 4 * hRowL           // 50+4×35 = 190

    // --- Бар: поля от краёв (#bar padding 0 18, было 18 фикс) ---
    readonly property int barPad: f(18)

    // --- Отступы (дополнение к 6/8/10…): паддинги панелей/чипов ---
    readonly property int s16: 16

    // --- Ключевые ширины (базовая × px: шрифт метки растёт вместе с колонкой) ---
    readonly property int wLabel: f(84)  // метка-колонка label caps (Docker/SysInfo)
    readonly property int wBar: f(360)  // окно статус-бара (Task 24: было 500)

    // --- Радиусы ---
    readonly property int r2: 2

    // --- Стекло (SPEC §9): false не создаёт текстуры стекла вообще ---
    readonly property bool glass: false

    // --- Глич-шейдер появления панелей (Task 9, SPEC §8): kill-критерий как у стекла —
    // если шейдер дороже ~2ms/кадр на этой машине — false отключает шейдер целиком
    // (остаётся lite-вариант без GPU), текстуры при false не создаются
    readonly property bool glitch: true
}
