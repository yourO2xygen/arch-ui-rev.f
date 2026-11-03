// ARCH·UI v2 — kit/Panel.qml (SPEC §2/§3/§4)
// Окно-каркас слота: head 40 / body (pad 12·16·16) / foot 30.
//
// Хореография (SPEC §2/§3, ANALYSIS §3.1):
//   · открытие из пустого слота: панель opacity 0→1 + scale .97→1, 420ms apple;
//     контент (head/body/foot) — fade 220ms, снимается таймером на 140-й мс;
//     ghost-эхо — 2 контурных Rect 1px (scale .99→.952, opacity .45→0, +40/+140, 620ms).
//   · замена: старая ячейка уходит 180ms (fade + scale .97), новая активируется
//     на +120ms выше по z (Loader-стек, клип по слоту), БЕЗ ghost-эхо.
//   · закрытие — зеркало открытия.
//   · глич появления (Task 9): поверх fade+scale, ShaderEffect на layer волны,
//     ТОЛЬКО во время перехода (_glitchRun); Theme.glitch=false → lite-flicker.
// Loader.active после первого открытия панели никогда не гаснет (состояние живёт).
//
// Маска ввода: пустая, пока слот закрыт; прямоугольник панели — с первого кадра
// открытия и до конца анимации закрытия (SPEC §2: «никогда не полагаемся на ввод
// по геометрии»).
//
// Использование (shell.qml):
//   Panel {
//       slot: "A"; panels: ["docker", "taskmgr"]
//       WlrLayershell.namespace: "archui:col-a"
//       anchors { left: true; top: true }; margins.left: 24; margins.top: 332
//       implicitWidth: 504; implicitHeight: 544
//       body: Component { Placeholder {} }
//   }

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// Motion.apple в канонической записи (см. комментарий в Motion.qml).
// ⚠ inline component в этом Qt объявляется только внутри корневого объекта файла.

PanelWindow {
    id: panel

    component AppleNumberAnimation: NumberAnimation {
        easing.type: Easing.Bezier
        easing.bezierCurve: Motion.apple
    }

    // ------------------------------------------------------------- public API
    property string slot: ""          // "A" | "B" | "C"
    property var panels: []           // panelId'ы слота (стек Loader'ов, порядок = z при равенстве)
    property Component head: null     // общий head-кит слота, 40px
    property Component body: null     // контент панели; инстанс на каждый panelId стека
    property string overlayPanelId: "" // panelId, владеющий overlay (задаёт glassH — Task 25)
    property Component overlay: null  // контент на всё окно слота (без head/foot/pad/clip) —
                                      // лаунчер T7: dock у нижней кромки слота, список 504×372
                                      // растёт от неё; геометрия SPEC §4 в границах body не помещается
    property Component foot: null     // общий foot-кит слота, 30px

    readonly property string panelId: LayoutState.slots[panel.slot] ?? ""
    readonly property bool open: panelId !== ""

    // Анатомия (ANALYSIS §5): head 40 / body pad 12 16 16 / foot 30 —
    // базовые высоты через Theme.hHead/hFoot (× px, Task 17): шрифт head растёт
    // вместе с хромом слота, контент body сжимается согласованно.
    readonly property int headH: Theme.hHead
    readonly property int footH: Theme.hFoot
    readonly property int padTop: 12
    readonly property int padLeft: 16
    readonly property int padRight: 16
    readonly property int padBottom: 16

    // Стаггер замены (SPEC §2: новая стартует на +120ms выше по z) — Motion.replaceStagger

    // -------------------------------------------------------------- состояние
    property string _current: ""      // panelId, показанный сейчас ("" — слот закрыт)
    property var _opened: []          // panelId'ы, открывавшиеся хоть раз — Loader.active не гасим
    property bool _maskActive: false  // прямоугольная маска ввода
    property real _contentStage: 0    // 0..1 — стадия контента (хореография 140/220)
    property var _nextCell: null      // ячейка, ожидающая replaceTimer
    property bool _glitchRun: false   // GlitchFX активен ТОЛЬКО во время перехода (SPEC §8)
    property real _glitchProgress: 1  // 0→1 за Motion.glitchPanel; 1 = нейтрально/выкл

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Клавиатура — по клику в панель (фильтры/поля T5+); хоткеи Hyprland не страдают.
    // Исключение — слот B: Exclusive на время открытия лаунчера (биндинг в shell.qml).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    visible: false

    // Динамическая высота видимого стекла/маски (Task 25): overlay-панель
    // (launcher) выставляет glassH и растит её сам внутри фикс-высотного окна —
    // анимация высоты самого layershell-окна в Hyprland дрожит (позиция
    // применяется раньше новой геометрии буфера). −1 = обычное поведение (всё окно).
    // На закрытии (panelId "") glassH ещё живёт у смонтированного overlay —
    // wave уходит в замороженной геометрии стекла; при replace на чужой panelId
    // стекло мгновенно на всё окно (новой панели нужен полный фон).
    readonly property real _glassH: overlayLoader.item && "glassH" in overlayLoader.item
                                   && (panel.panelId === panel.overlayPanelId || panel.panelId === "")
        ? overlayLoader.item.glassH
        : -1

    mask: Region {
        x: 0
        y: panel._glassH >= 0 ? panel.height - panel._glassH : 0
        width: panel._maskActive ? panel.width : 0
        height: panel._maskActive ? (panel._glassH >= 0 ? panel._glassH : panel.height) : 0
    }

    // ---------------------------------------------------------------- дерево
    Item {
        id: wave
        anchors.fill: parent
        opacity: 0
        scale: 0.97
        transformOrigin: Item.Center
        // Фокус внутри окна (OnDemand активируется кликом в панель), чтобы Esc
        // дошёл сюда даже без клика в конкретный элемент ввода.
        focus: true
        // Esc — штатное закрытие слота (Task 15). Если фокус в kit/Field, Esc
        // съедает поле (escPressed) и панель не закрывается — осознанно.
        Keys.onEscapePressed: LayoutState.closeSlot(panel.slot)

        // Глич появления (Task 9): слой+шейдер ТОЛЬКО пока идёт переход (_glitchRun);
        // вне перехода обычный рендер, GPU-налога нет (SPEC §8). Theme.glitch=false —
        // шейдер не создаётся вовсе (kill-критерий ~2ms/кадр), остаётся lite-flicker.
        layer.enabled: panel._glitchRun && Theme.glitch
        layer.effect: GlitchFX {
            progress: panel._glitchProgress
        }

        // Поверхность. Task 25: стекло приклеено к низу окна с высотой _glassH
        // (overlay-панели растят стекло сами, не ресайзя окно). −1 = всё окно.
        // ⚠ QTBUG-137166: у прозрачного Rect не трогать border → border.width: 0.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: panel._glassH >= 0 ? panel._glassH : parent.height
            color: Theme.surface
            border.width: 0
        }

        // Ghost-эхо: 2 контурных Rect 1px Theme.ghostLine (ANALYSIS §3.2).
        // Только на открытие из пустого слота; на replace отключено (SPEC §2).
        Rectangle {
            id: ghostA
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: panel._glassH >= 0 ? panel._glassH : parent.height
            color: "transparent"
            border.color: Theme.ghostLine
            border.width: 1
            opacity: 0
            transformOrigin: Item.Center
            visible: opacity > 0
        }
        Rectangle {
            id: ghostB
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: panel._glassH >= 0 ? panel._glassH : parent.height
            color: "transparent"
            border.color: Theme.ghostLine
            border.width: 1
            opacity: 0
            transformOrigin: Item.Center
            visible: opacity > 0
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: panel._contentStage

            Loader {
                id: headLoader
                active: panel.head !== null
                sourceComponent: panel.head
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: panel.headH
            }

            // Клип по слоту — replace-анимации ячеек не вылезают за геометрию панели
            Item {
                id: bodyArea
                clip: true
                anchors.top: headLoader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footLoader.top
                anchors.topMargin: panel.padTop
                anchors.leftMargin: panel.padLeft
                anchors.rightMargin: panel.padRight
                anchors.bottomMargin: panel.padBottom

                Repeater {
                    id: stack
                    model: panel.panels

                    delegate: Item {
                        id: cell
                        required property string modelData
                        readonly property bool isCurrent: panel.panelId === modelData

                        property Item loader: bodyLoader

                        anchors.fill: parent
                        opacity: 0
                        transformOrigin: Item.Center
                        z: 1
                        visible: opacity > 0.001

                        Loader {
                            id: bodyLoader
                            anchors.fill: parent
                            opacity: 0          // стадия контента — анимируется из choreography
                            active: panel._opened.indexOf(cell.modelData) !== -1
                            sourceComponent: panel.body
                            onLoaded: {
                                if (item && "panelId" in item) item.panelId = cell.modelData
                            }
                        }
                    }
                }
            }

            Loader {
                id: footLoader
                active: panel.foot !== null
                sourceComponent: panel.foot
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: panel.footH
            }

            // Оверлей на всё окно (см. property overlay). Едет в общей волне слота —
            // opacity контента (_contentStage) применяется к `content` целиком.
            Loader {
                id: overlayLoader
                active: panel.overlay !== null
                sourceComponent: panel.overlay
                anchors.fill: parent
                z: 3
            }
        }
    }

    // ------------------------------------------------------------- анимации
    // Волна панели: открытие из пустого слота
    ParallelAnimation {
        id: waveIn
        AppleNumberAnimation { target: wave; property: "opacity"; to: 1; duration: Motion.panelOpen }
        AppleNumberAnimation { target: wave; property: "scale"; to: 1; duration: Motion.panelOpen }
    }

    // Закрытие — зеркало; по завершении гасим окно и маску
    ParallelAnimation {
        id: waveOut
        AppleNumberAnimation { target: wave; property: "opacity"; to: 0; duration: Motion.panelOpen }
        AppleNumberAnimation { target: wave; property: "scale"; to: 0.97; duration: Motion.panelOpen }
        onStopped: panel._afterClose()
    }

    // Контент: fade 220, снимается таймером на 140-й мс (открытие из пустого)
    SequentialAnimation {
        id: contentIn
        PauseAnimation { duration: Motion.contentDelay }
        ParallelAnimation {
            AppleNumberAnimation { target: panel; property: "_contentStage"; to: 1; duration: Motion.contentFade }
            AppleNumberAnimation { id: openInner; to: 1; duration: Motion.contentFade }
        }
    }

    // Контент при замене: только входящая ячейка (хром не мигает), тот же 140/220
    SequentialAnimation {
        id: replaceInner
        PauseAnimation { duration: Motion.contentDelay }
        AppleNumberAnimation { id: replaceInnerAnim; to: 1; duration: Motion.contentFade }
    }

    // Контент уходит первым при закрытии (зеркало)
    AppleNumberAnimation {
        id: contentOut
        target: panel
        property: "_contentStage"
        to: 0
        duration: Motion.replaceExit
    }

    // Ghost-эхо: два контура, задержки 40/140, 620ms (Motion.ghostFade)
    ParallelAnimation {
        id: ghostRun
        SequentialAnimation {
            PauseAnimation { duration: Motion.ghostDelay1 }
            ParallelAnimation {
                AppleNumberAnimation { target: ghostA; property: "scale"; from: Motion.ghostScaleFrom; to: Motion.ghostScaleTo; duration: Motion.ghostFade }
                AppleNumberAnimation { target: ghostA; property: "opacity"; from: Motion.ghostOpacityFrom; to: 0; duration: Motion.ghostFade }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.ghostDelay2 }
            ParallelAnimation {
                AppleNumberAnimation { target: ghostB; property: "scale"; from: Motion.ghostScaleFrom; to: Motion.ghostScaleTo; duration: Motion.ghostFade }
                AppleNumberAnimation { target: ghostB; property: "opacity"; from: Motion.ghostOpacityFrom; to: 0; duration: Motion.ghostFade }
            }
        }
    }

    // Замена: старая ячейка (180ms fade + scale .97)
    ParallelAnimation {
        id: cellOut
        AppleNumberAnimation { id: cellOutOpacity; property: "opacity"; to: 0; duration: Motion.replaceExit }
        AppleNumberAnimation { id: cellOutScale; property: "scale"; to: 0.97; duration: Motion.replaceExit }
    }

    // Замена: новая ячейка (полная волна 420ms, выше по z)
    ParallelAnimation {
        id: cellIn
        AppleNumberAnimation { id: cellInOpacity; property: "opacity"; to: 1; duration: Motion.panelOpen }
        AppleNumberAnimation { id: cellInScale; property: "scale"; to: 1; duration: Motion.panelOpen }
    }

    // Глич открытия: progress 0→1 линейно за Motion.glitchPanel (350ms), по концу
    // слой выключается — шейдер больше не активен (SPEC §8: живёт только в переходе)
    NumberAnimation {
        id: glitchRun
        target: panel
        property: "_glitchProgress"
        to: 1
        duration: Motion.glitchPanel
        onStopped: panel._glitchRun = false
    }

    // Fallback без шейдера (Theme.glitch=false): lite-flicker волны ПОСЛЕ её хода
    // (те же свойства, что у waveIn — встречные тики недопустимы), как у тостов/бара
    SequentialAnimation {
        id: glitchLiteRun
        PauseAnimation { duration: Motion.panelOpen }
        NumberAnimation { target: wave; property: "opacity"; to: 0.72; duration: Motion.glitchLite / 4 }
        NumberAnimation { target: wave; property: "opacity"; to: 1; duration: Motion.glitchLite / 4 }
        NumberAnimation { target: wave; property: "opacity"; to: 0.85; duration: Motion.glitchLite / 4 }
        NumberAnimation { target: wave; property: "opacity"; to: 1; duration: Motion.glitchLite / 4 }
    }

    function _glitchStart() {
        if (!Theme.glitch) { glitchLiteRun.restart(); return }
        glitchRun.stop()
        panel._glitchRun = true
        panel._glitchProgress = 0
        glitchRun.restart()
    }

    function _glitchStop() {
        glitchRun.stop()
        glitchLiteRun.stop()
        panel._glitchRun = false
        panel._glitchProgress = 1
    }

    Timer {
        id: replaceTimer
        interval: Motion.replaceStagger
        onTriggered: panel._replaceEnter()
    }

    // ---------------------------------------------------------- хореография
    function _cellFor(pid) {
        for (let i = 0; i < panel.panels.length; i++) {
            const c = stack.itemAt(i)
            if (c && c.modelData === pid) return c
        }
        return null
    }

    function _ensureOpened(pid) {
        if (panel._opened.indexOf(pid) === -1)
            panel._opened = panel._opened.concat([pid])
    }

    function sync() {
        const cur = panel.panelId
        if (cur === panel._current) return
        const prev = panel._current
        panel._current = cur

        // Чужой/неизвестный panelId в персисте: ячейки нет — не «заклиниваем» слот,
        // а честно закрываем его (LayoutState тоже сбрасывает состояние).
        // closeSlot пишёт в persist — зовём отложенно: синхронный write в notify-цепочке
        // биндинга slots даёт binding loop.
        if (cur !== "" && _cellFor(cur) === null) {
            console.warn(`[Panel ${panel.slot}] unknown panelId "${cur}" — closing slot`)
            panel._current = ""
            Qt.callLater(LayoutState.closeSlot, panel.slot)
            return
        }

        if (prev === "" && cur !== "") playOpen(cur, true)
        else if (prev !== "" && cur === "") playClose()
        else playReplace(prev, cur)
    }

    function playOpen(pid, withGhost) {
        _ensureOpened(pid)
        const cell = _cellFor(pid)
        if (!cell) {
            console.warn(`[Panel ${panel.slot}] no cell for "${pid}"`)
            return
        }
        panel._maskActive = true
        panel.visible = true

        // прерванное закрытие не должно добить окно по onStopped;
        // встречные анимации на тех же свойствах не должны тикать одновременно
        waveOut.stop()
        contentOut.stop()
        replaceTimer.stop()

        wave.opacity = 0
        wave.scale = 0.97
        cell.z = 2
        cell.opacity = 1
        cell.scale = 1
        cell.loader.opacity = 0

        waveIn.restart()
        openInner.target = cell.loader
        openInner.property = "opacity"
        contentIn.restart()
        if (withGhost) ghostRun.restart()
        _glitchStart()   // Task 9: глич поверх fade+scale (совместим с 140/220 контента)
    }

    function playClose() {
        replaceTimer.stop()
        // встречные анимации на тех же свойствах не должны тикать одновременно
        waveIn.stop()
        contentIn.stop()
        ghostRun.stop()
        _glitchStop()
        contentOut.restart()
        waveOut.restart()
    }

    function playReplace(oldPid, newPid) {
        replaceTimer.stop()
        _ensureOpened(newPid)
        const oc = _cellFor(oldPid)
        const nc = _cellFor(newPid)
        if (!oc || !nc) {
            console.warn(`[Panel ${panel.slot}] replace: missing cell ("${oldPid}" → "${newPid}") — closing slot`)
            panel._current = ""
            Qt.callLater(LayoutState.closeSlot, panel.slot)
            return
        }
        panel._maskActive = true
        panel.visible = true
        panel._contentStage = 1   // хром слота не мигает — меняется только контент

        // быстрая замена a→b→a: недобитые анимации ячеек не должны тикать встречно
        cellOut.stop()
        cellIn.stop()
        replaceInner.stop()
        // SPEC §2: на replace ghost-эха нет — не доигрывать волну открытия
        ghostRun.stop()
        ghostA.opacity = 0
        ghostB.opacity = 0
        _glitchStop()   // хром слота не мигает — replace без глича

        oc.z = 2                  // исходящая — НИЖЕ входящей (ревью: z-конфликт a→b→a)

        cellOutOpacity.target = oc
        cellOutScale.target = oc
        cellOut.restart()

        panel._nextCell = nc
        replaceTimer.restart()
    }

    function _replaceEnter() {
        const nc = panel._nextCell
        panel._nextCell = null
        if (!nc || panel._current === "") return

        nc.z = 3
        nc.opacity = 0
        nc.scale = 0.97
        nc.loader.opacity = 0

        cellInOpacity.target = nc
        cellInScale.target = nc
        cellIn.restart()

        replaceInnerAnim.target = nc.loader
        replaceInnerAnim.property = "opacity"
        replaceInner.restart()
    }

    function _afterClose() {
        // закрытие прервали повторным открытием — окно остаётся жить
        if (panel.open) return
        panel.visible = false
        panel._maskActive = false
        panel._contentStage = 0
        wave.scale = 0.97
        for (let i = 0; i < panel.panels.length; i++) {
            const c = stack.itemAt(i)
            if (c) {
                c.z = 1
                c.opacity = 0
                c.scale = 1
                c.loader.opacity = 0
            }
        }
    }

    Connections {
        target: LayoutState
        function onSlotsChanged() { panel.sync() }
    }
    Component.onCompleted: sync()
}
