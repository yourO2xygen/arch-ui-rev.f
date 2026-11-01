// ARCH·UI v2 — components/StatusBar.qml (SPEC §2/§7, ANALYSIS §5.1, DESIGN-RESEARCH §3.9)
// Контент транзиентного бара 500×44: слева часы DSEG7 · по центру воркспейсы ·
// справа раскладка (пункт №8: без даты/дня недели в баре).
//
// Данные: SystemClock (тик 1s) + Hyprland.workspaces / focusedMonitor.activeWorkspace +
// rawEvent("activelayout"). Клик воркспейса → HyprlandWorkspace.activate()
// (было: Hyprland.dispatch("workspace N") + 250ms-гонка — на Hyprland 0.57 lua-эра
// legacy-строка падает, hyprwm/Hyprland#14675).
//
// Поведение: автоскрытие Motion.barTimeout (hover держит — таймер стоп, уход — полные
// 2800 заново, ANALYSIS §7.14; повторный toggleBar — рестарт); ghost-эхо на открытие —
// те же параметры, что у панелей (ANALYSIS §3.2: #bar::before/::after); микро-flicker
// 60ms часов на смене минуты (DESIGN-RESEARCH §3.9).
//
// Использование (shell.qml): StatusBar { anchors.fill: parent } в окне "archui:bar".

import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."
import "../kit" as Kit

Item {
    id: root

    // --------------------------------------------------------------- геометрия
    readonly property int padH: 18   // #bar{padding:0 18} — поля, если бар станет автоширины

    // ------------------------------------------------------------------- время
    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")

    // Смена минуты — микро-flicker (сигнала onMinutesChanged у SystemClock нет —
    // notify общий dateChanged, поэтому локальное свойство со своим changed).
    property int minuteNow: clock.minutes
    // глич-появления сам фликерит content — встречный тик минуты не мешаем
    onMinuteNowChanged: if (!barGlitch.running) minuteFlicker.restart()

    // -------------------------------------------------------------- воркспейсы
    // Занятость = воркспейс существует в Hyprland (пустые он удаляет сам, так что
    // «существует» ≈ «в использовании»). Активность — по фокусированному монитору.
    readonly property var wsIds: {
        const ids = []
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++) ids.push(list[i].id)
        return ids
    }

    function wsOccupied(id) { return root.wsIds.indexOf(id) !== -1 }

    // Базово показываем 4; занятые айди правее добавляются, предел — прежние 6
    // (пункт №8: `Math.max(4, maxOccupiedId)`, пустые 5+ не показываем).
    readonly property int wsCount: {
        let max = 4
        for (let i = 0; i < root.wsIds.length; i++)
            if (root.wsIds[i] > max) max = root.wsIds[i]
        return Math.min(6, max)
    }

    // Активный воркспейс — из событий (focusedMonitor.activeWorkspace у этой сборки
    // подтормаживает, а на старте модель Hyprland пустая и заполняется асинхронно).
    property int _eventWs: -1

    function _modelActiveId() {
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++)
            if (list[i].focused || list[i].active) return list[i].id
        return -1
    }

    readonly property int activeWsId:
        _eventWs !== -1 ? _eventWs
        : Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id
        : Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.activeWorkspace !== null
          ? Hyprland.focusedMonitor.activeWorkspace.id
        : _modelActiveId()

    // Переключение воркспейса: канонический HyprlandWorkspace.activate() (Quickshell
    // 0.3.2) — сам учитывает lua-эру (usingLua), без 250ms-гонки с подтормаживающей
    // моделью. Воркспейса нет в модели (пустой — Hyprland удаляет сам) → остаётся
    // только dispatch: activate() требует существующий объект.
    function currentWsId() { return root.activeWsId }

    function switchTo(id) {
        if (currentWsId() === id) return
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                list[i].activate()
                return
            }
        }
        Hyprland.dispatch("workspace " + id)
    }

    // --------------------------------------------------------------- раскладка
    // Активная раскладка приходит событием; на этой машине индус-0 = us → EN.
    property string layout: "EN"

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Hyprland 0.57 (lua-эра) шлёт "changeworkspaceid" с данными "из,в",
            // легаси-сборки — "workspace" с данными = id цели.
            if (event.name === "changeworkspaceid") {
                // источник истины по активному воркспейсу — событие, не модель
                const parts = event.parse(2)
                const id = parts.length === 2 ? parseInt(parts[1]) : NaN
                if (!isNaN(id)) root._eventWs = id
            } else if (event.name === "workspace") {
                const id = parseInt(event.data)
                if (!isNaN(id)) root._eventWs = id
            } else if (event.name === "activelayout") {
                // данные: "имя-клавиатуры,имя-раскладки"
                const parts = event.parse(2)
                if (parts.length === 2 && parts[1].length >= 2)
                    root.layout = parts[1].substring(0, 2).toUpperCase()
            } else if (event.name.indexOf("workspace") !== -1) {
                // create/destroy/open/close workspace (любая номенклатура) — пересобрать модель
                Hyprland.refreshWorkspaces()
            }
        }
    }

    // ------------------------------------------------------------------ дерево
    // Пункт №8: слева часы · по центру воркспейсы · справа раскладка. Единая обвязка
    // anchors left/center/right (Task 19 положит сюда OSD-контент той же ширины).
    Item {
        id: content
        anchors.fill: parent

        // x-jitter lite-глича (Translate, не x — anchors держат позиции)
        transform: Translate { id: jitter }

        // -------------------------------------------------- слева: часы DSEG7
        Text {
            id: timeText
            anchors.left: parent.left
            anchors.leftMargin: root.padH
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: Theme.txt
            font.family: Theme.fontDseg
            font.pixelSize: Theme.fs15
            font.bold: true
            font.letterSpacing: 0.3   // ls .02em от 15px
        }

        // ------------------------------------ по центру: воркспейсы (базово 4)
        // 22×22 gap 4; on — инверсия+700, occ — raise/txt2, пустой — dim
        Row {
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: root.wsCount

                delegate: Rectangle {
                    id: wsCell
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool active: root.activeWsId === wsCell.wsId
                    readonly property bool occupied: root.wsOccupied(wsCell.wsId)
                    readonly property bool hovered: wsMa.containsMouse

                    width: Theme.hChip
                    height: Theme.hChip
                    color: active ? Theme.invBg
                         : occupied || hovered ? Theme.raise : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.wsId
                        color: parent.active ? Theme.invFg
                             : parent.occupied || parent.hovered ? Theme.txt2 : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fs10
                        font.weight: parent.active ? Font.Bold : Font.DemiBold
                    }

                    MouseArea {
                        id: wsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchTo(parent.wsId)
                    }
                }
            }
        }

        // ------------------------------------------- справа: раскладка (#bar .bl)
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.padH
            anchors.verticalCenter: parent.verticalCenter
            text: root.layout
            color: Theme.txt
            font.family: Theme.font
            font.pixelSize: Theme.fs11
            font.weight: Font.Medium
        }
    }

    // -------------------------------------------------------- ghost-эхо открытия
    // Аналог панельного (Motion.ghostDelay1/2, scale .99→.952, opacity .45→0).
    Rectangle {
        id: ghostA
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.ghostLine
        border.width: 1
        opacity: 0
        transformOrigin: Item.Center
        visible: opacity > 0
    }
    Rectangle {
        id: ghostB
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.ghostLine
        border.width: 1
        opacity: 0
        transformOrigin: Item.Center
        visible: opacity > 0
    }

    ParallelAnimation {
        id: ghostRun
        SequentialAnimation {
            PauseAnimation { duration: Motion.ghostDelay1 }
            ParallelAnimation {
                NumberAnimation { target: ghostA; property: "scale"; from: Motion.ghostScaleFrom; to: Motion.ghostScaleTo; duration: Motion.ghostFade }
                NumberAnimation { target: ghostA; property: "opacity"; from: Motion.ghostOpacityFrom; to: 0; duration: Motion.ghostFade }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.ghostDelay2 }
            ParallelAnimation {
                NumberAnimation { target: ghostB; property: "scale"; from: Motion.ghostScaleFrom; to: Motion.ghostScaleTo; duration: Motion.ghostFade }
                NumberAnimation { target: ghostB; property: "opacity"; from: Motion.ghostOpacityFrom; to: 0; duration: Motion.ghostFade }
            }
        }
    }

    // ------------------------------------------- lite-глич открытия бара (Task 9)
    // Без шейдера: flicker + x-jitter ±2px + 2 инверсные полосы, Motion.glitchLite.
    Rectangle {
        id: barBandA
        anchors.left: parent.left
        anchors.right: parent.right
        y: parent.height * 0.25
        height: 2
        color: Theme.txt
        opacity: 0
        visible: opacity > 0
    }
    Rectangle {
        id: barBandB
        anchors.left: parent.left
        anchors.right: parent.right
        y: parent.height * 0.65
        height: 2
        color: Theme.txt
        opacity: 0
        visible: opacity > 0
    }
    SequentialAnimation {
        id: barGlitch
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: content; property: "opacity"; to: 1; duration: 60 }
                NumberAnimation { target: content; property: "opacity"; to: 0.72; duration: 25 }
                NumberAnimation { target: content; property: "opacity"; to: 1; duration: 25 }
            }
            SequentialAnimation {
                NumberAnimation { target: jitter; property: "x"; to: -2; duration: 60 }
                NumberAnimation { target: jitter; property: "x"; to: 2; duration: 25 }
                NumberAnimation { target: jitter; property: "x"; to: -1; duration: 25 }
                NumberAnimation { target: jitter; property: "x"; to: 0; duration: 25 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                NumberAnimation { target: barBandA; property: "opacity"; to: 0.9; duration: 30 }
                NumberAnimation { target: barBandA; property: "opacity"; to: 0; duration: 50 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 105 }
                NumberAnimation { target: barBandB; property: "opacity"; to: 0.9; duration: 30 }
                NumberAnimation { target: barBandB; property: "opacity"; to: 0; duration: 40 }
            }
        }
    }

    // ------------------------------------------------- микро-flicker смены минуты
    // 60ms: один провал opacity до .75 (DESIGN-RESEARCH §3.9 — «щелчок табло»).
    SequentialAnimation {
        id: minuteFlicker
        NumberAnimation { target: content; property: "opacity"; to: 0.75; duration: Motion.clockFlicker }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: Motion.clockFlicker }
    }

    // -------------------------------------------------- автоскрытие / hover-hold
    Timer {
        id: hideTimer
        interval: Motion.barTimeout
        onTriggered: LayoutState.closeBar()
    }

    // hover над баром держит: вход — стоп, выход — полные 2800 заново (ANALYSIS §7.14).
    // HoverHandler, а не MouseArea: неэксклюзивен по hover — ячейки воркспейсов под ним
    // (MouseArea, z ниже) продолжают получать containsMouse/cursor.
    HoverHandler {
        id: hoverHold
        onHoveredChanged: root._syncHover()
    }

    function _syncHover() {
        if (LayoutState.slots.bar === null) return
        if (hoverHold.hovered) hideTimer.stop()
        else hideTimer.restart()
    }

    Connections {
        target: LayoutState
        function onSlotsChanged() {
            if (LayoutState.slots.bar === "bar") {
                ghostRun.restart()   // повторный toggleBar — рестарт таймера + эхо
                barGlitch.restart()  // lite-глич появления (Task 9)
                hideTimer.restart()
            } else {
                hideTimer.stop()
                barGlitch.stop()
            }
        }
    }

    // Модель Hyprland на старте пустая — заполняется асинхронно; пока не заполнилась,
    // дотягиваем refresh'ами (дешёвые monoclient-запросы, прекращаются после первого успеха).
    Timer {
        id: initRetry
        property int attempts: 0
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            attempts++
            if ((root.activeWsId !== -1 && root.wsIds.length > 0) || attempts > 40) {
                if (attempts > 40 && root.activeWsId === -1)
                    console.warn("[archui] statusBar: модель Hyprland не заполнилась — жду событий")
                stop()
                return
            }
            Hyprland.refreshWorkspaces()
            Hyprland.refreshMonitors()
        }
    }

    Component.onCompleted: {
        if (LayoutState.slots.bar === "bar") hideTimer.restart()
    }
}
