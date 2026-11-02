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
import Quickshell.Io
import Quickshell.Services.Pipewire
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

    // -------------------------------------------------------------------- ОСД
    // Пункт №9 (Task 19): два экстра-режима над бар-контентом — громкость/яркость.
    // mode volatile (не персистим): окно/маска не переоткрываются, barLayer/osdLayer
    // друг над другом, кросс-fade Motion.osdSwap. Автоскрытие — тот же hideTimer
    // (hover-hold действует и на ОСД); по триггеру mode="bar" + closeBar().
    property string mode: "bar"        // "bar" | "volume" | "brightness"
    property real osdVolume: 0        // 0..1 (wpctl -l 1 — выше не бывает)
    property bool osdMuted: false
    property real osdBrightness: 0    // 0..1 (sysfs raw/max)

    readonly property string osdPctText:
        String(root.mode === "volume"
               ? Math.min(999, Math.round(root.osdVolume * 100))
               : Math.round(root.osdBrightness * 100))
    readonly property string osdIconName:
        root.mode === "brightness" ? "sun"
        : root.mode === "volume" && root.osdMuted ? "volume-x"
        : root.mode === "volume" && root.osdVolume <= 0.34 ? "volume-1"
        : "volume-2"
    readonly property real osdFill:
        root.mode === "volume" ? root.osdVolume : root.osdBrightness

    // Показ ОСД: бар скрыт → открыть (toggleBar, один раз); тот же режим — пульс
    // табло; иной — swap-фейд; рестарт автоскрытия (единый hideTimer).
    function _showOsd(m) {
        if (LayoutState.slots.bar === null) LayoutState.toggleBar()
        if (root.mode === m) osdPulse.restart()
        else root.mode = m
        hideTimer.restart()
    }

    // Показ бара обычным контентом (смена воркспейса/раскладки — требование №9):
    // единая точка возврата mode="bar" + рестарт автоскрытия.
    function _showBar() {
        if (LayoutState.slots.bar === null) LayoutState.toggleBar()
        root.mode = "bar"
        hideTimer.restart()
    }

    // Публичная точка для IPC `archui osd <kind>` (shell.qml) и локальных триггеров.
    function showOsd(kind) {
        if (kind === "brightness") {
            // sysfs без inotify → debounce 150ms (brightnessctl к этому моменту уже
            // применился — бинд зовёт через &&), затем показ и полл-удержание,
            // пока mode==="brightness". Явный вызов показываем всегда (дискретное
            // событие); фильтр «реально изменилось» — на поллинге повторов.
            brightDebounce.restart()
        } else if (kind === "volume") {
            const sink = Pipewire.defaultAudioSink
            if (sink !== null) {
                root.osdVolume = Math.max(0, sink.audio.volume)
                root.osdMuted = sink.audio.muted
            }
            root._showOsd("volume")
        }
    }

    // ------------------------------------------------------- громкость (push)
    // Pipewire ловит любой источник (wpctl-бинд, pavucontrol, приложения), бинды
    // громкости не трогаем. |Δv| > 0.005 фильтрует wpctl-повторы на границе шкалы
    // (100%+ при уже 100% не всплывает); mute — дискретное событие, показываем всегда.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink ?? null] }

    Connections {
        target: Pipewire.defaultAudioSink !== null ? Pipewire.defaultAudioSink.audio : null
        property real lastVol: -1   // база без показа (первое notify при бинде узла)
        function onVolumesChanged() {
            const sink = Pipewire.defaultAudioSink
            if (sink === null) return
            const v = Math.max(0, sink.audio.volume)
            if (lastVol < 0) { lastVol = v; return }
            if (Math.abs(v - lastVol) > 0.005) {
                lastVol = v
                root.osdVolume = v
                root.osdMuted = sink.audio.muted
                root._showOsd("volume")
            }
        }
        function onMutedChanged() {
            const sink = Pipewire.defaultAudioSink
            if (sink === null) return
            root.osdMuted = sink.audio.muted
            root._showOsd("volume")
        }
    }

    // ---------------------------------------------------- яркость (sysfs poll)
    // Quickshell 0.3.2 без Brightness-сервиса; sysfs не поддерживает inotify →
    // FileView + поллинг ~300ms только пока mode==="brightness". Триггер показа —
    // IPC из бинда (hyprland.lua append `&& qs ... osd brightness`), дебаунс 150ms.
    // Task 21: blockLoading делает синхронным только ПЕРВЫЙ read (дальше text()
    // вечно отдаёт кеш — он не следит за файлом без watchChanges, а sysfs нельзя
    // inotify). Идиома свежего чтения: перед каждым text() дергать reload()
    // (сбрасывает кеш) при blockAllReads (тогда text() делает loadSync —
    // синхронный read с диска; FileView::shouldBlockRead, src/io/fileview.cpp).
    FileView {
        id: sysBrightness
        path: "/sys/class/backlight/intel_backlight/brightness"
        preload: false
        blockLoading: true
        blockAllReads: true
    }
    FileView {
        id: sysMaxBrightness
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        preload: false
        blockLoading: true
        blockAllReads: true
    }

    property real _lastBright: -1   // последний показанный/зафиксированный (0..1)

    function _brightnessNow() {
        // Task 21: reload() перед text() — иначе text() отдаёт кеш первого
        // чтения (см. комментарий к FileView выше).
        sysBrightness.reload()
        sysMaxBrightness.reload()
        const raw = parseFloat(sysBrightness.text())
        const max = parseFloat(sysMaxBrightness.text())
        if (!isFinite(raw) || !isFinite(max) || max <= 0) return -1
        return raw / max
    }

    function _applyBrightness(v, force) {
        if (v < 0) return
        const changed = Math.abs(v - root._lastBright) > 0.0005
        root._lastBright = v
        // Явный триггер (IPC из бинда) — показываем всегда; полл повторов —
        // только если значение реально изменилось (стартовый baseline — тоже).
        if (force || changed) {
            root.osdBrightness = v
            root._showOsd("brightness")
        }
    }

    Timer {
        id: brightDebounce
        interval: 150
        onTriggered: root._applyBrightness(root._brightnessNow(), true)
    }
    Timer {
        id: brightPoll
        interval: 300
        repeat: true
        running: root.mode === "brightness"   // дёшево: только пока ОСД яркости жив
        onTriggered: root._applyBrightness(root._brightnessNow(), false)
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
                if (!isNaN(id)) {
                    root._eventWs = id
                    root._showBar()   // №9: смена воркспейса — бар обычным контентом
                }
            } else if (event.name === "workspace") {
                const id = parseInt(event.data)
                if (!isNaN(id)) {
                    root._eventWs = id
                    root._showBar()
                }
            } else if (event.name === "activelayout") {
                // данные: "имя-клавиатуры,имя-раскладки"
                const parts = event.parse(2)
                if (parts.length === 2 && parts[1].length >= 2)
                    root.layout = parts[1].substring(0, 2).toUpperCase()
                root._showBar()   // №9: смена раскладки — бар обычным контентом
            } else if (event.name.indexOf("workspace") !== -1) {
                // create/destroy/open/close workspace (любая номенклатура) — пересобрать модель
                Hyprland.refreshWorkspaces()
            }
        }
    }

    // ------------------------------------------------------------------ дерево
    // Пункт №8: слева часы · по центру воркспейсы · справа раскладка. Единая обвязка
    // anchors left/center/right (Task 19 положит сюда OSD-контент той же ширины).
    //
    // Task 19: barLayer + osdLayer друг над другом (окно/маска не переоткрываются),
    // кросс-fade Motion.osdSwap. Отдельные слои — чтобы fade не конфликтовал с
    // barGlitch/minuteFlicker, которые анимируют content.
    Item {
        id: barLayer
        anchors.fill: parent
        opacity: root.mode === "bar" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.osdSwap
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }

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
    }   // barLayer

    // ------------------------------------------------- ОСД-слой (Task 19, №9)
    // Строка той же полосы 500: иконка + сегмент-бар свечей + процент DSEG7 (как
    // табло часов — единый образный цифровой стиль полосы). Монохром, Kit.Icon /
    // Kit.SegBar. Слой включается тем же кросс-fade, что выключает barLayer.
    Item {
        id: osdLayer
        anchors.fill: parent
        opacity: root.mode === "bar" ? 0 : 1
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.osdSwap
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }

        Row {
            id: osdRow
            anchors.centerIn: parent
            spacing: Math.round(10 * Theme.px)

            Kit.Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.osdIconName
                size: Theme.fs15
            }

            Kit.SegBar {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(240 * Theme.px)
                value: root.osdFill
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.osdPctText
                color: Theme.txt
                font.family: Theme.fontDseg
                font.pixelSize: Theme.fs15
                font.bold: true
                font.letterSpacing: 0.3
                // DSEG7 — только цифры; ширина стабилизирована lS, «100» не прыгает
                horizontalAlignment: Text.AlignHCenter
                width: Theme.fs15 * 4
            }
        }
    }

    // Пульс табло ОСД при повторном триггере того же режима (как полумиг часов):
    // провал и возврат по половине, Motion.osdPulse.
    SequentialAnimation {
        id: osdPulse
        NumberAnimation { target: osdRow; property: "opacity"; to: 0.45; duration: Motion.osdPulse }
        NumberAnimation { target: osdRow; property: "opacity"; to: 1; duration: Motion.osdPulse }
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
        // Task 19: по тайм-ауту ОСД тоже возвращается к mode="bar" (volatile)
        onTriggered: {
            root.mode = "bar"
            LayoutState.closeBar()
        }
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
        // база яркости без показа: первый osd brightness покажется только
        // если значение реально изменилось от стартового
        root._lastBright = root._brightnessNow()
    }
}
