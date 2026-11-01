// ARCH·UI v2 — components/StatusBar.qml (SPEC §2/§7, ANALYSIS §5.1, DESIGN-RESEARCH §3.9)
// Контент транзиентного бара 500×44: воркспейсы 1–6 · разделитель · раскладка ·
// разделитель · часы DSEG7 + дата.
//
// Данные: SystemClock (тик 1s) + Hyprland.workspaces / focusedMonitor.activeWorkspace +
// rawEvent("activelayout"). Клик воркспейса → Hyprland.dispatch("workspace N").
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
import "datefmt.js" as DateFmt

Item {
    id: root

    // --------------------------------------------------------------- геометрия
    readonly property int padH: 18   // #bar{padding:0 18} — поля, если бар станет автоширины
    readonly property int gap: 13    // #bar{gap:13}

    // ------------------------------------------------------------------- время
    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")
    // `sun · nov 1` — строчные англ. сокращения, без локали (ANALYSIS §7.2, datefmt.js)
    readonly property int clockY: parseInt(Qt.formatDateTime(clock.date, "yyyy"))
    readonly property int clockM: parseInt(Qt.formatDateTime(clock.date, "M")) - 1
    readonly property int clockD: parseInt(Qt.formatDateTime(clock.date, "d"))
    readonly property string dateText: DateFmt.shortDate(clockY, clockM, clockD)

    // Смена минуты — микро-flicker (сигнала onMinutesChanged у SystemClock нет —
    // notify общий dateChanged, поэтому локальное свойство со своим changed).
    property int minuteNow: clock.minutes
    onMinuteNowChanged: minuteFlicker.restart()

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

    // Переключение воркспейса. Hyprland 0.57 сломал legacy-строку ("dispatch workspace N"
    // заворачивается в lua и падает разбором — hyprwm/Hyprland#14675), поэтому: legacy
    // → через 250ms проверка; не переключило — lua-диспетчер этой сборки.
    property int _pendingWs: -1

    function currentWsId() { return root.activeWsId }

    function switchTo(id) {
        if (currentWsId() === id) return
        Hyprland.dispatch("workspace " + id)
        _pendingWs = id
        wsFallback.restart()
    }

    Timer {
        id: wsFallback
        interval: 250
        onTriggered: {
            if (root._pendingWs < 0 || root.currentWsId() === root._pendingWs) return
            const from = root.currentWsId()
            Hyprland.dispatch(
                `hl.dsp.workspace.change_id({workspace=${from}, id=${root._pendingWs}})`)
            wsWarn.restart()
        }
    }

    // Оба пути не сработали (например, lua-бридж собрки изменился) — предупредить раз.
    Timer {
        id: wsWarn
        interval: 300
        onTriggered: {
            if (root._pendingWs < 0 || root.currentWsId() === root._pendingWs) return
            console.warn(
                `[archui] statusBar: dispatch workspace ${root._pendingWs} не сработал ` +
                `(legacy + lua-фолбэк)`)
            root._pendingWs = -1
        }
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
    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.gap

        // воркспейсы 1–6: 22×22 gap 4; on — инверсия+700, occ — raise/txt2, пустой — dim
        Row {
            spacing: 4

            Repeater {
                model: 6

                delegate: Rectangle {
                    id: wsCell
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool active: root.activeWsId === wsCell.wsId
                    readonly property bool occupied: root.wsOccupied(wsCell.wsId)
                    readonly property bool hovered: wsMa.containsMouse

                    width: 22
                    height: 22
                    color: active ? Theme.invBg
                         : occupied || hovered ? Theme.raise : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.wsId
                        color: parent.active ? Theme.invFg
                             : parent.occupied || parent.hovered ? Theme.txt2 : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10
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

        // #bar .sep — 1×16 rgba(255,255,255,.09) = Theme.raise2
        Rectangle { width: 1; height: 16; color: Theme.raise2 }

        // раскладка: 500 11px, txt (#bar .bl)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.layout
            color: Theme.txt
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        Rectangle { width: 1; height: 16; color: Theme.raise2 }

        // часы + дата: baseline-выравнивание, gap 8 (#clock)
        Item {
            width: timeText.width + 8 + dateText.width
            height: 22

            Text {
                id: timeText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.timeText
                color: Theme.txt
                font.family: Theme.fontDseg
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 0.3   // ls .02em от 15px
            }

            Text {
                id: dateText
                anchors.left: timeText.right
                anchors.leftMargin: 8
                anchors.baseline: timeText.baseline
                text: root.dateText
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 0.63  // ls .06em от 10.5px
            }
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
                hideTimer.restart()
            } else {
                hideTimer.stop()
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
