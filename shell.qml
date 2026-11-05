//@ pragma AppId archui
// ARCH·UI v2 — точка входа (SPEC §1/§2/§7).
// Окна: 3 колонки-слота (A/B/C) + calendar + bar + toasts — все создаются один раз и
// живут всегда (демон), exclusionMode: Ignore, namespace "archui:*", маска ввода пустая
// на закрытых слотах. IPC-таргет "archui", GlobalShortcut лаунчера (обработчик запуска —
// задача 7). Сетка — расчёт от фактического логического экрана (базовый дизайн
// 1600×900@1.2); шрифты/высоты масштабируются Theme.px (Task 17).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "kit" as Kit

ShellRoot {
    id: root

    // --- Геометрия от фактического логического экрана (Task 17) ---
    // Источник — Quickshell.screens[0] (тот же экран, к которому аттачатся все
    // PanelWindow демона; стартовый лог ниже печатает именно его). Окна НЕ
    // автомасштабируются с монитором — px-множитель шрифтов/высот живёт в Theme,
    // позиции/отступы считаются здесь от реального width/height:
    //   pad    = round(W·24/1600)                — базовый отступ макета 24
    //   слот A: x = pad;   B: (W−slotW)/2;   C:  W − pad − slotW
    //   y слотов = H − slotH − pad;  slotW/H = round(504/544 · Theme.px)
    // На базовом 1600×900@1.2 (px=1) это ровно старые числа: 24 / 548 / 1072, y=332.
    readonly property var scr: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    readonly property int scrW: scr !== null ? scr.width : 1600
    readonly property int scrH: scr !== null ? scr.height : 900
    readonly property int pad: Math.round(scrW * 24 / 1600)
    readonly property int slotW: Math.round(504 * Theme.px)
    readonly property int slotH: Math.round(544 * Theme.px)
    readonly property int slotY: scrH - slotH - pad

    // --- Слот B: компактное окно (Task 24, втрое ниже 544) ---
    // launcher = фикс-окно Theme.hSlotB (dock + 4 строки): рост видимого стекла
    // при первом символе делает сам Launcher (glassH) внутри окна, окно НЕ
    // ресайзится — Task 25: анимация высоты layershell-окна давала дрожь
    // (compositor применяет новую позицию раньше нового буфера).
    // logout = хром + 2 ряда плиток по центру (241). При закрытии
    // (slots.B = null) высота ЗАМОРАЖИВАЕТСЯ — окно уходит волной в прежней геометрии.
    // Паддинги 12/16 — те же литералы, что body кит kit/Panel.qml.
    property int colBH: Theme.hDock
    function _syncColBH() {
        const pid = LayoutState.slots.B
        if (pid === "launcher")
            colBH = Theme.hSlotB
        else if (pid === "logout")
            colBH = Theme.hHead + 12 + 2 * Theme.hTile + Theme.s6 + 16 + Theme.hFoot
    }
    Connections {
        target: LayoutState
        function onSlotsChanged() { root._syncColBH() }
    }

    // DND: сегмент-кнопка [OFF|ON] (design-proposal 2026-11-05 REV.E/F, .seg2) —
    // бегунок 32×18 (Track+Thumb) отвергнут: две равные половины в одном ложе,
    // АКТИВНАЯ половина ИНВЕРСНАЯ (заливка invBg #f4f4f5, текст invFg #000) —
    // состояние читается позицией ЗАЛИВКИ и словом на самой кнопке; неактивная —
    // прозрачная с ghost-caps «OFF»/«ON» (8–9px). Между половинами волосяной шов
    // ghost, при hover+on гаснет — инверсная половина глотает стык.
    // Анимация 100ms apple (REV motion: dnd 100; Motion.dndToggle=160 — по макету).
    // Label «dnd» (что это) живёт в head РЯДОМ, отдельно от дескриптора off/on.
    component DndSeg: Rectangle {
        id: seg

        property bool on: false
        readonly property bool hovered: segMa.containsMouse
        readonly property real halfW: 27   // .seg2 span 27px — половина клетки

        width: halfW * 2 + 3   // 27+27 половины + шов 1 + внешние рамки 2
        height: 20
        color: "transparent"
        border.width: 1
        // hover — контур-инверсия: внутренняя рамка 1px ghost → txt
        border.color: seg.hovered ? Theme.txt : Theme.ghost
        Behavior on border.color { ColorAnim {} }

        // половина OFF (инверсна, когда dnd выключен)
        Rectangle {
            x: 1
            y: 1
            width: seg.halfW
            height: parent.height - 2
            color: !seg.on
                   ? Theme.invBg
                   : segMa.pressed ? Theme.raise : "transparent"
            Behavior on color { ColorAnim {} }
            Text {
                anchors.centerIn: parent
                text: "OFF"
                color: !seg.on ? Theme.invFg : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                Behavior on color { ColorAnim {} }
            }
        }

        // волосяной шов между половинами; на активной стороне гаснет
        // (CSS .seg2.on:hover span+span{border-left-color:transparent})
        Rectangle {
            x: 1 + seg.halfW
            y: 1
            width: 1
            height: parent.height - 2
            color: seg.hovered && seg.on ? "transparent" : Theme.ghost
            Behavior on color { ColorAnim {} }
        }

        // половина ON (инверсна, когда dnd включен)
        Rectangle {
            x: 2 + seg.halfW
            y: 1
            width: seg.halfW
            height: parent.height - 2
            color: seg.on
                   ? Theme.invBg
                   : segMa.pressed ? Theme.raise : "transparent"
            Behavior on color { ColorAnim {} }
            Text {
                anchors.centerIn: parent
                text: "ON"
                color: seg.on ? Theme.invFg : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                Behavior on color { ColorAnim {} }
            }
        }

        MouseArea {
            id: segMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: LayoutState.setDnd(!seg.on)
        }
    }

    // 100ms apple — общий примитив анимации сегмента (см. выше)
    component ColorAnim: ColorAnimation {
        duration: 100
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.apple
    }

    // Кнопка Clear (h26, .btn)
    component ClearButton: Rectangle {
        id: cb
        signal clicked()
        readonly property bool hovered: cbMa.containsMouse
        width: cbText.width + 16
        height: 26
        color: cb.hovered ? Theme.raise2 : Theme.raise
        Text {
            id: cbText
            anchors.centerIn: parent
            text: "CLEAR"
            color: Theme.txt2
            font.family: Theme.font
            font.pixelSize: Theme.fs10
            font.weight: Font.Medium
        }
        MouseArea {
            id: cbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    Component.onCompleted: {
        root._syncColBH()   // персист мог открыть слот B при старте (Task 24)
        console.info(
        Quickshell.screens.length === 0
        ? "[archui] shell loaded · no screens (headless)"
        : `[archui] shell loaded · screen ${Quickshell.screens[0].name} ` +
          `${Quickshell.screens[0].width}x${Quickshell.screens[0].height} ` +
          `@${Quickshell.screens[0].scale}`)
    }

    // --------------------------------------------------------------- СЛОТ A
    Kit.Panel {
        id: colA
        slot: "A"
        panels: ["sysinfo"]
        WlrLayershell.namespace: "archui:col-a"
        anchors { left: true; top: true }
        margins.left: root.pad
        margins.top: root.slotY
        implicitWidth: root.slotW
        implicitHeight: root.slotH

        head: Component {
            Item {
                // sysinfo — единственная панель слота A: i-gauge + SYSINFO · справа чип uptime
                Row {
                    visible: colA.panelId === "sysinfo"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "gauge"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SYSINFO"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                Kit.Chip {
                    visible: colA.panelId === "sysinfo"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "up " + SysMon.fmtUptime(SysMon.uptimeSec)
                }
            }
        }
        // sysinfo — единственная реальная панель слота A (задача 5, перенесена из слота B — Task 12)
        body: Component {
            Item {
                id: bodyA
                property string panelId: ""

                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId === "sysinfo"
                    sourceComponent: SysInfo {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId !== "sysinfo"
                    sourceComponent: Placeholder { panelId: bodyA.panelId }
                }
            }
        }
        foot: Component {
            Item {
                // Пустой panelId (закрытие слота) — футер не флэшит фолбэки (Task 15)
                Text {
                    visible: colA.panelId !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: Quickshell.env("USER") + "@" + SysMon.hostName
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
                Text {
                    visible: colA.panelId !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "kernel " + SysMon.kernel
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
            }
        }
    }

    // --------------------------------------------------------------- СЛОТ B
    Kit.Panel {
        id: colB
        slot: "B"
        panels: ["launcher", "logout"]
        // Лаунчер (T7) — Exclusive на время открытия, при закрытии назад OnDemand (SPEC §2).
        // Остальным панелям слота остаётся OnDemand из kit/Panel.qml.
        WlrLayershell.keyboardFocus: LayoutState.slots.B === "launcher"
                                     ? WlrKeyboardFocus.Exclusive
                                     : WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "archui:col-b"
        // launcher (владелец overlay) рисует стекло сам (glassH) внутри фикс-окна:
        // окно НЕ анимируется по высоте (Task 25), маска/стекло растут по glassH.
        overlayPanelId: "launcher"
        anchors { left: true; top: true }
        margins.left: Math.round((root.scrW - root.slotW) / 2)
        // y от низа: нижняя кромка приклеена к scrH−pad. Высота окна статична
        // на время жизни панели — margin читает неанимируемую implicitHeight.
        margins.top: root.scrH - colB.implicitHeight - root.pad
        implicitWidth: root.slotW
        implicitHeight: root.colBH

        head: Component {
            Item {
                // head по умолчанию (logout; launcher — оверлей без head, задача 7).
                Text {
                    visible: colB.panelId !== "launcher"
                             && colB.panelId !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colB.panelId.toUpperCase()
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: Theme.fs11
                    font.letterSpacing: 1
                }
            }
        }
        // launcher — реальная панель (задача 7, оверлей); logout — реальная панель (задача 7)
        body: Component {
            Item {
                id: bodyB
                property string panelId: ""

                Loader {
                    anchors.fill: parent
                    active: bodyB.panelId === "logout"
                    sourceComponent: Logout {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyB.panelId !== "logout"
                            && bodyB.panelId !== "launcher"
                    sourceComponent: Placeholder { panelId: bodyB.panelId }
                }
            }
        }
        // launcher/logout (задача 7): launcher — оверлей на всё окно (dock у нижней
        // кромки слота), logout — панель в body; подвал logout: user · uptime.
        // Деактивация оверлея отсрочена: при replace launcher→чужое Loader гаснет
        // через Motion.replaceExit (иначе дырка 0–120ms — старая ячейка уже ушла,
        // оверлей снят мгновенно); при простом закрытии — с концом волны
        // (Motion.panelOpen), чтобы overlay уходил вместе с волной, а не висел.
        overlay: Component {
            Item {
                id: ovRoot
                readonly property bool wantActive: colB.panelId === "launcher"
                property bool mounted: wantActive

                onWantActiveChanged: {
                    if (wantActive) {
                        hideTimer.stop()
                        mounted = true
                    } else {
                        hideTimer.interval = colB.open ? Motion.replaceExit : Motion.panelOpen
                        hideTimer.restart()
                    }
                }

                Timer {
                    id: hideTimer
                    onTriggered: ovRoot.mounted = false
                }

                Loader {
                    active: ovRoot.mounted
                    anchors.fill: parent
                    sourceComponent: Launcher {}
                }
            }
        }
        foot: Component {
            Item {
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: colB.panelId !== "launcher"
                             && colB.panelId !== ""
                    text: colB.panelId === "logout"
                          ? Quickshell.env("USER") + " · up "
                            + SysMon.fmtUptime(SysMon.uptimeSec)
                          : ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
            }
        }
    }

    // Клик мимо лаунчера закрывает его (SPEC §2). Активен только пока launcher
    // открыт; cleared — слот B всё ещё launcher (не перехватывать чужие закрытия).
    HyprlandFocusGrab {
        active: LayoutState.slots.B === "launcher"
        windows: [colB]
        onCleared: {
            if (LayoutState.slots.B === "launcher") {
                console.info("[archui] launcher: focus grab cleared — closing")
                LayoutState.closeSlot("B")
            }
        }
    }

    // --------------------------------------------------------------- СЛОТ C
    // head/foot слота общие (kit/Panel): единственная панель слота —
    // notifcenter, её head и показывается.
    // Дебаг-фолбэк «SLOT C» (head при пустом panelId) убран: слот-окно видно
    // только при открытой панели, надпись лишь моргала в переходах (Task 15).
    Kit.Panel {
        id: colC
        slot: "C"
        panels: ["notifcenter"]
        WlrLayershell.namespace: "archui:col-c"
        anchors { left: true; top: true }
        margins.left: root.scrW - root.pad - root.slotW
        margins.top: root.slotY
        implicitWidth: root.slotW
        implicitHeight: root.slotH

        head: Component {
            Item {
                // notifcenter (ANALYSIS §5.5): i-bell + NOTIFICATIONS · dnd · Clear
                Row {
                    visible: colC.panelId === "notifcenter"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "bell"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "NOTIFICATIONS"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                Row {
                    visible: colC.panelId === "notifcenter"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "dnd"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fs8
                    }
                    DndSeg {
                        anchors.verticalCenter: parent.verticalCenter
                        on: NotifStore.dnd
                    }
                    ClearButton {
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: NotifStore.clearHistory()
                    }
                }
            }
        }
        body: Component {
            Item {
                id: bodyC
                property string panelId: ""
                Loader {
                    anchors.fill: parent
                    active: bodyC.panelId === "notifcenter"
                    sourceComponent: NotifCenter {}
                }
            }
        }
        foot: Component {
            Item {
                // Левого лейбла «archui» больше нет (Task 15 — юзер просил убрать);
                // счётчики справа остаются, пустой panelId их не рендерит.
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: colC.panelId !== ""
                    text: NotifStore.historyCount + " unread · dnd "
                          + (NotifStore.dnd ? "on" : "off")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
            }
        }
    }

    // ------------------------------------------------------------- CALENDAR
    // Скрыт по умолчанию (виден только по хоткею/IPC toggleCalendar — РФ на
    // «календарь показывается всегда»). Свертывание до чипа 264×40 — живое
    // состояние (components/Calendar.qml, не персистится); высота окна едет
    // за ним. Видимость — как у слотовых панелей: imperative visible-тумблер.
    PanelWindow {
        id: calendar
        WlrLayershell.namespace: "archui:calendar"
        visible: false
        anchors { left: true; top: true }
        margins.left: root.pad
        margins.top: root.pad
        implicitWidth: Math.round(264 * Theme.px)
        implicitHeight: calendarContent.collapsed ? Math.round(40 * Theme.px)
                                                  : Math.round(288 * Theme.px)
        Behavior on implicitHeight {
            NumberAnimation {
                duration: Motion.calendarCollapse
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { width: calendar.width; height: calendar.height }

        // Волосяная рамка блока 1px Theme.ghost — как .win в макете REV.F.
        // Rect непрозрачный (Theme.surface) — QTBUG-137166 не задевается.
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 1
            border.color: Theme.ghost
        }

        Calendar { id: calendarContent; anchors.fill: parent }
    }

    // ------------------------------------------------------------------ BAR
    // Транзиент: автоскрытие Motion.barTimeout (hover-hold, рестарт по toggleBar)
    // живёт в components/StatusBar.qml. Task 24: ширина 360·px (~375); было 500.
    // V4 (design-proposal 2026-11-05): бар прижат к НИЖНЕЙ кромке экрана по центру
    // («osc-edge»), было top-center; вся логика показа/скрытия (toggleBar/ОСД) та же.
    PanelWindow {
        id: bar
        WlrLayershell.namespace: "archui:bar"
        anchors { left: true; bottom: true }
        margins.bottom: 0
        margins.left: Math.round((root.scrW - bar.implicitWidth) / 2)
        implicitWidth: Theme.wBar
        implicitHeight: Math.round(44 * Theme.px)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: LayoutState.slots.bar !== null
        // SPEC §2: скрытый бар — пустая маска (не Region на весь скрытый слой)
        mask: Region {
            width: bar.visible ? bar.width : 0
            height: bar.visible ? bar.height : 0
        }

        // Волосяная рамка блока 1px Theme.ghost — как .win в макете REV.F.
        // Rect непрозрачный (Theme.surface) — QTBUG-137166 не задевается.
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 1
            border.color: Theme.ghost
        }

        StatusBar { id: statusBar; anchors.fill: parent }
    }

    // --------------------------------------------------------------- TOASTS
    // Стек тостов 276 top-right (задача 4). Высота окна едет за стеком; маска —
    // прямоугольник стека при наличии тостов, пустая при отсутствии (SPEC §2 —
    // от visible-факта, не от анимации; урок бара T3).
    PanelWindow {
        id: toasts
        WlrLayershell.namespace: "archui:toasts"
        anchors { right: true; top: true }
        margins.right: root.pad
        margins.top: root.pad
        implicitWidth: Math.round(276 * Theme.px)
        implicitHeight: Math.max(1, toastContent.contentHeight)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: true
        mask: Region {
            width: NotifStore.showing ? toasts.width : 0
            height: NotifStore.showing ? toasts.height : 0
        }

        Toasts { id: toastContent; anchors.fill: parent }
    }

    // ------------------------------------------------------------------- IPC
    IpcHandler {
        target: "archui"

        function toggle(panelId: string): void { LayoutState.toggle(panelId) }
        function toggleBar(): void { LayoutState.toggleBar() }
        // ОСД статус-бара (Task 19): показать бар в режиме volume/brightness
        function osd(kind: string): void { statusBar.showOsd(kind) }
        function dismissToasts(): void { NotifStore.dismissAll() }
        function dnd(on: bool): void { LayoutState.setDnd(on) }
        // Хоткеи SPEC §12: тумблеры (бинд не знает текущего состояния)
        function dndToggle(): void { LayoutState.setDnd(!LayoutState.dnd) }
        // Показать/скрыть окно целиком; при показе — всегда развёрнутым
        // (свертка в чип остаётся живым состоянием на время показа).
        function toggleCalendar(): void {
            if (!calendar.visible) calendarContent.collapsed = false
            calendar.visible = !calendar.visible
        }

    }

    // Реакция на хоткей — задача 7 (обработчик запуска лаунчера); бинд в hyprland.conf:
    //   bind = SUPER, R, global, archui:launcher
    GlobalShortcut {
        appid: "archui"
        name: "launcher"
        description: "Open the app launcher (slot B)"

        onPressed: LayoutState.toggle("launcher")
    }
}

