// ARCH·UI v2 — components/StatusBar.qml (DESIGN-PROPOSAL 2026-11-05 · bar V4 «osc-edge»)
// Кромка-приборка: окно Theme.wBar 360×44 (shell.qml) прижато к нижней кромке экрана
// ПО ЦЕНТРУ (V4 — переезд сверху вниз; заявка №1). Три равные ячейки ws | lng | clk:
// silk-метка 8px caps dim над tabular-значением JBM 700 (~16px; моноширинный JBM сам
// даёт tabular-стабилизацию ширины), швы — волосяные 1px ghost во всю высоту, ws-ячейка
// ИНВЕРСНАЯ (единственный акцент, «03» с ведущим нулём целиком инверсно). Внизу —
// шкала суток «осциллографическая кромка»: 24 тика, каждый 4-й выше, тик текущего
// часа инверсный, позиция по реальному времени (hours/minutes → позиция, без таймера —
// binding на SystemClock). LCD/DSEG7 снят полностью — в т.ч. процент ОСД теперь
// tabular-цифры (заявка №4: LCD уходит из системы вообще).
//
// Данные: SystemClock (тик 1s) + Hyprland.workspaces / focusedMonitor.activeWorkspace +
// rawEvent("activelayout"/"changeworkspaceid"). Клик ws-ячейки → Hyprland.dispatch
// ("workspace r+1") — цикл по существующим на мониторе (V4 показывает только текущий
// номер; списковая сетка 22×22 из V2-бара ушла; activate() больше не нужен — r+1 ходит
// по живым воркспейсам, пустых Hyprland не хранит).
//
// Поведение прежнее (заявка №1): автоскрытие Motion.barTimeout (hover держит — таймер
// стоп, уход — полные 2800 заново; повторный toggleBar — рестарт), ghost-эхо и
// lite-глич на открытие, микро-flicker на смену минуты; ОСД — второй volatile-режим
// этого же бара (кросс-fade Motion.osdSwap 130ms), тот же hideTimer.
//
// Использование (shell.qml): StatusBar { anchors.fill: parent } в окне "archui:bar"
// (окно — bottom-center, anchors left+bottom, margins.top ушли в margins.bottom).

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
    // Ширина окна — Theme.wBar (360·px). Инлайн-токены V4 (в Theme их нет — выражаю
    // здесь от Theme.px, DESIGN design-proposal-2026-11-05 §.sbar/.bc/.day):
    //   fsSilk  — silk-метка 8px caps (глобальный .silk: 8px/.16em/ghost-dim)
    //   dayH    — высота шкалы суток ~10px (в макете .day 8px + волосяная кромка;
    //             по заявке беру 10)
    readonly property int padH: Theme.barPad
    readonly property int fsSilk: Math.round(8 * Theme.px)
    readonly property int dayH: Math.round(10 * Theme.px)
    // тик суток: обычный 3px, каждый 4-й (maj) 6px — от макета .day i{h:3} i.q{h:6}
    readonly property int dayTickMinor: Math.max(2, Math.round(3 * Theme.px))
    readonly property int dayTickMaj: Math.max(4, Math.round(6 * Theme.px))

    // ------------------------------------------------------------------- время
    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")

    // Смена минуты — микро-flicker (сигнала onMinutesChanged у SystemClock нет —
    // notify общий dateChanged, поэтому локальное свойство со своим changed).
    property int minuteNow: clock.minutes
    // глич-появления сам фликерит content — встречный тик минуты не мешаем
    onMinuteNowChanged: if (!barGlitch.running) minuteFlicker.restart()

    // Час/минуты для шкалы суток: позиция текущего тика = clock.hours, заполнение
    // тика внутри часа — clock.minutes (binding-ом, отдельного таймера не нужно:
    // SystemClock тикает раз в секунду и сам инвалидирует оба выражения).
    readonly property int hourNow: clock.hours
    readonly property real hourFrac: clock.minutes / 60

    // -------------------------------------------------------------- воркспейсы
    // V4 показывает только НОМЕР текущего воркспейса (с ведущим нулём, «03»),
    // целиком в инверсной ячейке. Занятость/сетка V2-бара ушли; модель нужна лишь
    // initRetry'ю на старте (Hyprland заполняется асинхронно).
    readonly property var wsIds: {
        const ids = []
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++) ids.push(list[i].id)
        return ids
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

    // «03» — ведущий ноль, как в макете; на пустой модели (старт) — прочерк.
    readonly property string wsText:
        root.activeWsId > 0
        ? (root.activeWsId < 10 ? "0" + root.activeWsId : "" + root.activeWsId)
        : "--"

    // Клик ws-ячейки: цикл по существующим воркспейсам монитора (r+1 ходит только по
    // живым; пустые Hyprland удаляет сам). activate()-гонка V2 больше не нужна.
    function cycleWs() {
        Hyprland.dispatch("workspace r+1")
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
    // вечно отдаёт кеш — он не следует за файлом без watchChanges, а sysfs нельзя
    // inotify). Идиома свежего чтения: перед каждым text() дергать reload().
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
        // Task 21: reload() перед text() — иначе text() отдаёт кеш первого чтения.
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
    // V4 «osc-edge»: сверху ячейки (три равные, во весь бар, на волосяных швах),
    // внизу — полоса шкалы суток. Task 19: barLayer + osdLayer друг над другом
    // (окно/маска не переоткрываются), кросс-fade Motion.osdSwap. Отдельные слои —
    // чтобы fade не конфликтовал с barGlitch/minuteFlicker, которые анимируют content.
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

            // x-jitter lite-глюча (Translate, не x — anchors держат позиции)
            transform: Translate { id: jitter }

            // ------------------------------------------ область ячеек (без day-полосы)
            // .v4c: sbar над .day — ячейки занимают верх, шкала суток — нижняя
            // полоса высотой dayH.
            Item {
                id: cellStrip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: dayScale.top

                Row {
                    anchors.fill: parent

                    BarCell {
                        width: (cellStrip.width - 2) / 3   // минус два шва 1px
                        height: cellStrip.height
                        label: "ws"
                        valueText: root.wsText
                        inv: true            // ws-ячейка инверсная — единственный акцент
                        clickable: true
                        onActivated: root.cycleWs()
                    }
                    Rectangle { width: 1; height: parent.height; color: Theme.ghost }
                    BarCell {
                        width: (cellStrip.width - 2) / 3
                        height: cellStrip.height
                        label: "lng"
                        valueText: root.layout.toLowerCase()
                    }
                    Rectangle { width: 1; height: parent.height; color: Theme.ghost }
                    BarCell {
                        width: (cellStrip.width - 2) / 3
                        height: cellStrip.height
                        label: "clk"
                        valueText: root.timeText
                    }
                }
            }

            // ---------------------------------------------- шкала суток (.day, V4)
            // 24 тика на всю ширину: обычный 3px / каждый 4-й (maj) 6px / текущий час
            // инверсный; сверх того — заполнение тика минутами (hours/minutes →
            // позиция без таймера: binding на SystemClock тикает раз в секунду).
            Item {
                id: dayScale
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.dayH

                // волосяная кромка сверху полосы (.day borderTop)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: Theme.ghost
                }

                Row {
                    id: dayRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.top: parent.top
                    anchors.topMargin: 1

                    Repeater {
                        model: 24

                        Item {
                            id: dayTick
                            required property int index
                            readonly property bool current: dayTick.index === root.hourNow
                            readonly property bool maj: (dayTick.index + 1) % 4 === 0
                            width: dayRow.width / 24
                            height: parent.height

                            // тело тика: невысокий штрих от нижней кромки (raise2,
                            // как rgba(255,255,255,.09) в макете)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, parent.width - 2)   // зазор 2px между тиками
                                height: dayTick.maj ? root.dayTickMaj : root.dayTickMinor
                                color: Theme.raise2
                            }

                            // текущий час — инверсный тик с заполнением минутой:
                                // белый до доли minuteNow/60 ширины тика. Источник —
                                // binding без таймера: SystemClock сам инвалидирует hourFrac
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                width: Math.max(1, (parent.width - 2) * root.hourFrac)
                                height: dayTick.maj ? root.dayTickMaj : root.dayTickMinor
                                color: Theme.invBg
                                visible: dayTick.current
                            }                        }
                    }
                }
            }
        }
    }   // barLayer

    // ------------------------------------------------- ОСД-слой (Task 19, №9)
    // Строка той же полосы: иконка + сегмент-бар свечей + процент tabular (заявка №4:
    // DSEG7 снят; JBM-моноширинник сам даёт табулярную стабильность ширины, но ширину
    // блока фиксируем — «100» не сдвигает бар при кросс-fade). Монохром, Kit.Icon /
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
                font.family: Theme.font
                font.pixelSize: Theme.fs15
                font.weight: Font.Bold
                font.letterSpacing: 0.3
                // фикс-ширина блока — JBM mono табулярен, «5» и «100» не прыгают
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
    // HoverHandler, а не MouseArea: неэксклюзивен по hover — ячейки под ним
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
    // дотягиваем refresh'ами (дешёвые monoclient-запросы, прекращаются после первого
    // успеха). V4: нужен только активный id (сетка ячеек ушла).
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

    // ================================================================ ячейки V4
    // .bc: flex:1, column по центру, gap 3px; silk-метка над tabular-значением.
    // hover — контур-инверсия (outline 1px ink); .bc.inv:hover в макете гасит
    // заливку — инверсная ws-ячейка на hover «разинвиливается» к обычному виду.
    component BarCell: Rectangle {
        id: cell
        property string label
        property string valueText
        property bool inv: false
        property bool clickable: false
        signal activated()
        readonly property bool hovered: cellMa.containsMouse

        // .bc:hover{outline:1px solid var(--ink)} — контур внутрь (offset -1)
        border.width: !cell.inv && cell.hovered ? 1 : 0
        border.color: Theme.txt
        // .bc.inv{background:var(--ink)} / .bc.inv:hover{background:var(--bg)}
        color: cell.inv && !cell.hovered ? Theme.invBg : "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 3   // gap макета .bc

            Text {
                // silk: 8px caps ghost/dim (.bc .silk{color:var(--dim)},
                // инверсно — color bg + opacity .55)
                text: cell.label
                color: cell.inv && !cell.hovered ? Theme.invFg : Theme.dim
                opacity: cell.inv && !cell.hovered ? 0.55 : 1
                font.family: Theme.font
                font.pixelSize: root.fsSilk
                font.weight: Font.Medium
                font.letterSpacing: Math.max(1, fsSilk * 0.16)   // ls .16em
                font.capitalization: Font.AllUppercase
            }
            Text {
                // .bv: tabular 16px/700; JBM моноширинный — цифры стабильны и без
                // font-variant-numeric (инлайн-токен вместо него).
                text: cell.valueText
                color: cell.inv && !cell.hovered ? Theme.invFg : Theme.txt
                font.family: Theme.font
                font.pixelSize: Theme.fs15          // ≈16px при px≈1.04
                font.weight: Font.Bold
                font.letterSpacing: 0.3             // ls .02em от 16px
                horizontalAlignment: Text.AlignHCenter
            }
        }

        MouseArea {
            id: cellMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: cell.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (cell.clickable) cell.activated()
        }
    }
}
