//@ pragma AppId archui
// ARCH·UI v2 — точка входа (SPEC §1/§2/§7).
// Окна: 3 колонки-слота (A/B/C) + calendar + bar + toasts — все создаются один раз и
// живут всегда (демон), exclusionMode: Ignore, namespace "archui:*", маска ввода пустая
// на закрытых слотах. IPC-таргет "archui", GlobalShortcut лаунчера (обработчик запуска —
// задача 7). Сетка — логические px, scale 1.2 (экран 1600×900).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "kit" as Kit

ShellRoot {
    id: root

    // Тумблер DND (ANALYSIS §5.5 .sw: 32×18, бегунок 14×14, 160ms — Motion.dndToggle)
    component DndToggle: Rectangle {
        id: tg
        property bool on: false
        width: 32
        height: 18
        color: tg.on ? Theme.invBg : Theme.raise

        Rectangle {
            x: tg.on ? 16 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            color: tg.on ? Theme.invFg : Theme.txt2
            Behavior on x {
                NumberAnimation {
                    duration: Motion.dndToggle
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.apple
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: LayoutState.setDnd(!tg.on)
        }
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

    Component.onCompleted: console.info(
        Quickshell.screens.length === 0
        ? "[archui] shell loaded · no screens (headless)"
        : `[archui] shell loaded · screen ${Quickshell.screens[0].name} ` +
          `${Quickshell.screens[0].width}x${Quickshell.screens[0].height} ` +
          `@${Quickshell.screens[0].scale}`)

    // --------------------------------------------------------------- СЛОТ A
    Kit.Panel {
        id: colA
        slot: "A"
        panels: ["docker", "taskmgr", "sysinfo"]
        WlrLayershell.namespace: "archui:col-a"
        anchors { left: true; top: true }
        margins.left: 24
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                // head по умолчанию (docker до задачи 6).
                // Пустой panelId — не рендерим «SLOT A»: фолбэк-надпись моргала в
                // переходах слота (Task 15).
                Text {
                    visible: colA.panelId !== ""
                             && colA.panelId !== "taskmgr"
                             && colA.panelId !== "docker"
                             && colA.panelId !== "sysinfo"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colA.panelId === "" ? "SLOT A" : colA.panelId.toUpperCase()
                    color: Theme.txt2
                    font.family: Theme.font
                    font.pixelSize: Theme.fs11
                    font.letterSpacing: 1
                }

                // taskmgr (ANALYSIS 5.x): i-activity + TASKMGR
                Row {
                    visible: colA.panelId === "taskmgr"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "activity"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TASKMGR"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                // docker (ANALYSIS 5.x): i-container + DOCKER
                Row {
                    visible: colA.panelId === "docker"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "container"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "DOCKER"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                // sysinfo (ANALYSIS 5.3): i-gauge + SYSINFO · справа чип uptime
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
        // docker — реальная панель (задача 6); taskmgr — реальная панель (задача 5);
        // sysinfo — реальная панель (задача 5, перенесена из слота B — Task 12)
        body: Component {
            Item {
                id: bodyA
                property string panelId: ""

                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId === "taskmgr"
                    sourceComponent: TaskMgr {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId === "docker"
                    sourceComponent: Docker {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId === "sysinfo"
                    sourceComponent: SysInfo {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyA.panelId !== "taskmgr"
                            && bodyA.panelId !== "docker"
                            && bodyA.panelId !== "sysinfo"
                    sourceComponent: Placeholder { panelId: bodyA.panelId }
                }
            }
        }
        foot: Component {
            Item {
                // Пустой panelId (закрытие слота) — футер не флэшит фолбэки
                // («archui» / «slot a», Task 15)
                Text {
                    visible: colA.panelId !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colA.panelId === "taskmgr"
                          ? ProcMon.view.length + " / " + ProcMon.procs.length
                            + " · sorted by " + ProcMon.sortBy
                          : colA.panelId === "docker"
                          ? (DockerMon.dockerPresent
                             ? DockerMon.runningCount + " running · "
                               + DockerMon.exitedCount + " exited · v"
                               + DockerMon.version
                             : "docker " + (DockerMon.ghostReason === "no permission"
                                            ? "no permission" : "unavailable"))
                          : colA.panelId === "sysinfo"
                          ? Quickshell.env("USER") + "@" + SysMon.hostName
                          : "archui"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
                Text {
                    visible: colA.panelId !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colA.panelId === "taskmgr" ? "del · term"
                        : colA.panelId === "docker" ? "logs · res · ports"
                        : colA.panelId === "sysinfo" ? "kernel " + SysMon.kernel : "slot a"
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
        anchors { left: true; top: true }
        margins.left: 548
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                // head по умолчанию (logout; launcher — оверлей без head, задача 7).
                // Пустой panelId — не рендерим «SLOT B» (флэш в переходах, Task 15)
                Text {
                    visible: colB.panelId !== "launcher"
                             && colB.panelId !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: colB.panelId === "" ? "SLOT B" : colB.panelId.toUpperCase()
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
                          : "archui"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: colB.panelId !== "launcher"
                             && colB.panelId !== ""
                    text: "slot b"
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

    // Дисмисс слот-панелей (Task 15): клик ЛКМ вне открытых панелей archui
    // закрывает ВСЕ видимые панели слот-типа (слоты + календарь + бар) штатной
    // хореографией LayoutState. Идиома как у лаунчера: HyprlandFocusGrab пассивно
    // белит список окон (обычный ввод сохраняется), клик вне списка гасит grab
    // (onCleared). keyboardFocus слотов остаётся OnDemand — хоткеи Hyprland и фокус
    // тайлов не воруются. Grab активирован, пока открыта хоть одна панель; все
    // close* идемпотентны, поэтому повторный onCleared (гашение grab при штатном
    // закрытии) безвреден. Лаунчер закрывается собственным grab'ом выше — в
    // active-условие не входит, чтобы с ним не пересекаться.
    HyprlandFocusGrab {
        active: colA.open
                || LayoutState.slots.B === "logout"
                || colC.open
                || calendar.visible
                || LayoutState.slots.bar !== null
        windows: [colA, colB, colC, calendar, bar]
        onCleared: {
            if (colA.open || LayoutState.slots.B !== null || colC.open
                || calendar.visible || LayoutState.slots.bar !== null) {
                console.info("[archui] outside click — dismissing panels")
                LayoutState.closeSlot("A")
                LayoutState.closeSlot("B")
                LayoutState.closeSlot("C")
                calendar.visible = false
                LayoutState.closeBar()
            }
        }
    }

    // --------------------------------------------------------------- СЛОТ C
    // head/foot слота общие (kit/Panel): контент notifcenter показывается, когда
    // активен он (задача 8 добавит свои head'ы для chat/aimgr).
    // Дебаг-фолбэк «SLOT C» (head при пустом panelId) убран: слот-окно видно
    // только при открытой панели, надпись лишь моргала в переходах (Task 15).
    Kit.Panel {
        id: colC
        slot: "C"
        panels: ["chat", "aimgr", "notifcenter"]
        WlrLayershell.namespace: "archui:col-c"
        anchors { left: true; top: true }
        margins.left: 1072
        margins.top: 332
        implicitWidth: 504
        implicitHeight: 544

        head: Component {
            Item {
                // head чата (DESIGN §4 «chat»): бот+CHAT слева; справа чип модели
                // (инверсия), чип треда, «+» (New thread)
                Row {
                    visible: colC.panelId === "chat"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "bot"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CHAT"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                Row {
                    visible: colC.panelId === "chat"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // чип модели (инверсия) — клик открывает aimgr (выбор модели)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: cModelText.width + 16
                        height: Theme.hChip
                        radius: Theme.r2
                        color: Theme.invBg
                        border.width: 0
                        Text {
                            id: cModelText
                            anchors.centerIn: parent
                            text: AgentBridge.currentModel ? AgentBridge.currentModel.name : "—"
                            color: Theme.invFg
                            font.family: Theme.font
                            font.pixelSize: Theme.fs10
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: LayoutState.openIn("C", "aimgr")
                        }
                    }
                    Kit.Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        text: AgentBridge.generating ? "streaming"
                            : AgentBridge.dead ? "died"
                            : AgentBridge.stopped ? "stopped"
                            : AgentBridge.connected ? "thread · " + AgentBridge.messageCount
                            : "offline"
                        onClicked: AgentBridge.ensureStarted()
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: Theme.hChip
                        radius: Theme.r2
                        color: cPlusMa.containsMouse ? Theme.raise2 : Theme.raise
                        border.width: 0
                        Kit.Icon {
                            anchors.centerIn: parent
                            name: "plus"
                            size: 12
                            color: Theme.txt2
                        }
                        MouseArea {
                            id: cPlusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AgentBridge.newThread()
                        }
                    }
                }

                // head aimgr: AImgr слева, чип contextUsage справа (SPEC §6)
                Row {
                    visible: colC.panelId === "aimgr"
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Kit.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "sparkles"
                        size: 13
                        color: Theme.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "AGENT MGR"
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.letterSpacing: 1
                    }
                }

                Text {
                    visible: colC.panelId === "aimgr"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentBridge.contextUsage && AgentBridge.contextUsage.percent !== null
                          ? "context " + Math.round(AgentBridge.contextUsage.percent) + "%"
                          : "context —"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }

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
                    DndToggle {
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
                Loader {
                    anchors.fill: parent
                    active: bodyC.panelId === "chat"
                    sourceComponent: AgentChat {}
                }
                Loader {
                    anchors.fill: parent
                    active: bodyC.panelId === "aimgr"
                    sourceComponent: AgentMgr {}
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
                    text: colC.panelId === "notifcenter"
                          ? NotifStore.historyCount + " unread · dnd "
                            + (NotifStore.dnd ? "on" : "off")
                          : colC.panelId === "chat" || colC.panelId === "aimgr"
                          ? (AgentBridge.statusText.length > 0 ? AgentBridge.statusText
                             : AgentBridge.currentModel
                               ? AgentBridge.currentModel.provider + "/" + AgentBridge.currentModel.id
                               : (AgentBridge.connected ? "connected" : "offline"))
                          : "slot c"
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
        margins.left: 24
        margins.top: 24
        implicitWidth: 264
        implicitHeight: calendarContent.collapsed ? 40 : 288
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

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 0
        }

        Calendar { id: calendarContent; anchors.fill: parent }
    }

    // ------------------------------------------------------------------ BAR
    // Транзиент: автоскрытие Motion.barTimeout (hover-hold, рестарт по toggleBar)
    // живёт в components/StatusBar.qml. 500×44 top-center.
    PanelWindow {
        id: bar
        WlrLayershell.namespace: "archui:bar"
        anchors { left: true; top: true }
        margins.top: 0
        margins.left: Math.round(((bar.screen ? bar.screen.width : 1600) - bar.implicitWidth) / 2)
        implicitWidth: 500
        implicitHeight: 44
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        visible: LayoutState.slots.bar !== null
        // SPEC §2: скрытый бар — пустая маска (не Region на весь скрытый слой)
        mask: Region {
            width: bar.visible ? bar.width : 0
            height: bar.visible ? bar.height : 0
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.width: 0
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
        margins.right: 24
        margins.top: 24
        implicitWidth: 276
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

