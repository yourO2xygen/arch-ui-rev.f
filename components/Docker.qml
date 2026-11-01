// ARCH·UI v2 — components/Docker.qml (SPEC §4, DESIGN §4 «docker»)
// Панель контейнеров (слот A, panelId "docker"): слева список 184px (Dot состояния,
// имя, порт справа, разделитель 1px), справа тулбар h26 (имя 12/600 + чип состояния +
// start/stop/restart/attach) и табы Logs / Resources / Ports. Logs — терминальный
// блок 10px/1.7: время dim, warn — txt2 bold, error — инверсия. Resources — 4 строки
// «метка значение + SegBar» + health. Данные — push из DockerMon.
//
// Нет docker/нет прав → ghost: строки «—» и подпись причины, процессов не дёргаем.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    readonly property int listW: 184
    readonly property int rowH: 28
    readonly property int toolH: 26
    // иконочка тулбара 22×22 (пока одно использование — инлайн, в kit не выносим)
    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""          // подпись для ревью; тултипов в шелле нет
        property bool selected: false
        signal clicked()
        readonly property bool hovered: ibMa.containsMouse && enabled
        width: 22
        height: 22
        enabled: true
        color: !enabled ? "transparent"
             : selected ? Theme.invBg
             : hovered ? Theme.raise2 : "transparent"
        border.width: 0
        Kit.Icon {
            anchors.centerIn: parent
            name: ib.icon
            size: 12
            color: !ib.enabled ? Theme.ghost
                 : ib.selected ? Theme.invFg : Theme.txt2
        }
        MouseArea {
            id: ibMa
            anchors.fill: parent
            enabled: ib.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // выбранный контейнер живёт в DockerMon (смена выбора = смена хвоста логов)
    readonly property string selected: DockerMon.selected
    readonly property string tab: DockerMon.tab    // "logs" | "resources" | "ports"

    readonly property var sel: {
        const s = root.selected
        const cs = DockerMon.containers
        for (let i = 0; i < cs.length; i++) if (cs[i].name === s) return cs[i]
        return null
    }


    // автоселект: ничего не выбрано (или выбранное исчезло) → первый в списке
    readonly property var containers: DockerMon.containers
    onContainersChanged: {
        const cs = DockerMon.containers
        for (let i = 0; i < cs.length; i++)
            if (cs[i].name === DockerMon.selected) return
        DockerMon.selected = cs.length > 0 ? cs[0].name : ""
    }
    Component.onCompleted: {
        const cs = DockerMon.containers
        if (DockerMon.selected.length === 0 && cs.length > 0) DockerMon.selected = cs[0].name
    }

    // -------------------------------------------------------------- GHOST
    // Нет бинаря/нет прав к сокету: процессы не дёргаются, панель — приборка «—».
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: !DockerMon.dockerPresent

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "—  —  —"
            color: Theme.ghost
            font.family: Theme.font
            font.pixelSize: 18
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DockerMon.ghostReason === "no docker binary" ? "no docker"
                : DockerMon.ghostReason === "no permission" ? "no docker socket"
                : "docker unavailable"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10
            font.letterSpacing: 1
        }
    }

    // -------------------------------------------------------------- CONTENT
    Row {
        anchors.fill: parent
        visible: DockerMon.dockerPresent
        spacing: 0

        // ------------------------------------------------ список контейнеров 184
        Item {
            width: root.listW
            height: parent.height

            // пусто
            Text {
                anchors.centerIn: parent
                visible: DockerMon.containers.length === 0
                text: "no containers"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10
            }

            Flickable {
                anchors.fill: parent
                clip: true
                contentHeight: listCol.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: listCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right

                    Repeater {
                        model: DockerMon.containers

                        delegate: Item {
                            id: cRow
                            required property var modelData
                            readonly property var c: modelData
                            readonly property bool isSel: c.name === root.selected
                            readonly property bool hovered: cHover.hovered

                            width: root.listW
                            height: root.rowH

                            HoverHandler { id: cHover }

                            Rectangle {
                                anchors.fill: parent
                                color: cRow.isSel ? Theme.raise2
                                     : cRow.hovered ? Theme.raise : "transparent"
                                border.width: 0
                            }
                            // inset-маркер выбранной
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                visible: cRow.isSel
                                color: Theme.txt
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                Kit.Dot {
                                    anchors.verticalCenter: parent.verticalCenter
                                    state: cRow.c.state === "running" ? "on"
                                         : cRow.c.state === "paused" ? "idle" : "off"
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 2 - 46
                                    text: cRow.c.name
                                    color: cRow.isSel ? Theme.txt : Theme.txt2
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 46
                                    text: root.portOf(cRow.c.ports)
                                    color: Theme.dim
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                    font.family: Theme.font
                                    font.pixelSize: 9
                                }
                            }
                            // разделитель 1px (ANALYSIS: список с разделителями)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.raise
                                border.width: 0
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DockerMon.selected = cRow.c.name
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------ разделитель 1px
        Rectangle {
            width: 1
            height: parent.height
            color: Theme.raise
            border.width: 0
        }

        // ------------------------------------------------ правая часть
        Item {
            width: parent.width - root.listW - 1
            height: parent.height

            Column {
                anchors.fill: parent
                spacing: 0

                // ---------------------------------------- тулбар h26
                Item {
                    width: parent.width
                    height: root.toolH

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - stateChip.width - actions.width - 20
                        text: root.sel ? root.sel.name : "no container"
                        color: Theme.txt
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Kit.Chip {
                        id: stateChip
                        anchors.verticalCenter: parent.verticalCenter
                        // прижат к кнопкам, не к концу имени (имя elide)
                        x: parent.width - stateChip.width - actions.width - 12
                        text: root.sel ? root.sel.state : "—"
                        selected: root.sel ? root.sel.state === "running" : false
                    }
                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // start / stop / restart / attach (attach → таб Logs)
                        IconBtn { icon: "play"; tip: "start"
                            enabled: root.sel && root.sel.state !== "running"
                            onClicked: DockerMon.action("start", root.selected) }
                        IconBtn { icon: "square"; tip: "stop"
                            enabled: root.sel && root.sel.state === "running"
                            onClicked: DockerMon.action("stop", root.selected) }
                        IconBtn { icon: "refresh-cw"; tip: "restart"
                            enabled: root.sel && root.sel.state === "running"
                            onClicked: DockerMon.action("restart", root.selected) }
                        IconBtn { icon: "terminal"; tip: "attach"
                            enabled: root.sel !== null
                            selected: root.tab === "logs"
                            onClicked: DockerMon.tab = "logs" }
                    }
                }

                // ---------------------------------------- табы
                Row {
                    id: tabsRow
                    spacing: 6
                    topPadding: 2
                    leftPadding: 0

                    Repeater {
                        model: [
                            { t: "logs", label: "LOGS" },
                            { t: "resources", label: "RESOURCES" },
                            { t: "ports", label: "PORTS" }
                        ]
                        delegate: Kit.Chip {
                            required property var modelData
                            text: modelData.label
                            selected: root.tab === modelData.t
                            onClicked: DockerMon.tab = modelData.t
                        }
                    }
                }

                // ---------------------------------------- контент таба
                Item {
                    id: content
                    width: parent.width
                    height: parent.height - root.toolH - tabsRow.height

                    // ---------- LOGS
                    Flickable {
                        id: logView
                        anchors.fill: parent
                        visible: root.tab === "logs"
                        clip: true
                        contentHeight: logCol.height
                        boundsBehavior: Flickable.StopAtBounds

                        // автоскролл: держим низ, пока юзер не уехал вверх
                        readonly property bool atBottom:
                            contentY >= contentHeight - height - 24
                        onContentHeightChanged:
                            if (atBottom) Qt.callLater(() => {
                                logView.contentY =
                                    Math.max(0, logView.contentHeight - logView.height) })
                        onAtBottomChanged:
                            if (atBottom) Qt.callLater(() => {
                                logView.contentY =
                                    Math.max(0, logView.contentHeight - logView.height) })

                        Text {
                            visible: DockerMon.logLines.length === 0
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            text: root.sel && root.sel.state !== "running"
                                  ? "no logs (container not running)" : "no logs"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10
                        }

                        Column {
                            id: logCol
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Repeater {
                                model: DockerMon.logLines

                                // строка 10px × 1.7 = 17px; error — инверсия
                                delegate: Item {
                                    required property var modelData
                                    readonly property var ln: modelData
                                    width: logCol.width
                                    height: 17

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: ln.level === "error"
                                        color: Theme.invBg
                                        border.width: 0
                                    }
                                    Row {
                                        anchors.fill: parent
                                        Text {
                                            width: 64
                                            height: 17
                                            text: ln.ts
                                            color: ln.level === "error"
                                                   ? Theme.invFg : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 10
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            width: parent.width - 64
                                            height: 17
                                            text: ln.text
                                            color: ln.level === "error" ? Theme.invFg
                                                 : ln.level === "warn" ? Theme.txt2
                                                 : Theme.txt2
                                            font.family: Theme.font
                                            font.pixelSize: 10
                                            font.weight: ln.level === "warn" ? Font.Bold
                                                         : Font.Normal
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------- RESOURCES
                    Column {
                        anchors.fill: parent
                        visible: root.tab === "resources"
                        spacing: 0

                        // якоря в positioner-детях ломают весь Column («Column
                        // will not function») — отступ через padding, не anchors
                        Text {
                            visible: DockerMon.statsData === null
                            topPadding: 8
                            text: "no stats"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10
                        }

                        Repeater {
                            model: root.resRows

                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 30

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 84
                                    text: modelData.label
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Kit.SegBar {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 88
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 88 - 96
                                    value: modelData.frac
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.value
                                    color: Theme.txt2
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // health — строка после 4 метрик
                        Item {
                            width: parent.width
                            height: 30
                            visible: DockerMon.statsData !== null

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                text: "HEALTH"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 9
                                font.letterSpacing: 1
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 88
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.sel ? (root.sel.health === "none"
                                      ? "—" : root.sel.health) : "—"
                                color: root.sel && root.sel.health === "healthy"
                                       ? Theme.txt : Theme.txt2
                                font.family: Theme.font
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // ---------- PORTS
                    Column {
                        anchors.fill: parent
                        visible: root.tab === "ports"
                        spacing: 0

                        Text {
                            visible: root.portRows.length === 0
                            topPadding: 8
                            text: root.sel && root.sel.ports.length === 0
                                  ? "no published ports" : "no container"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10
                        }

                        Repeater {
                            model: root.portRows

                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 26

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 120
                                    text: modelData.host
                                    color: Theme.txt2
                                    elide: Text.ElideMiddle
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 124
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "→"
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 142
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.target
                                    color: Theme.txt2
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ хелперы
    function _pct(s) {
        const v = parseFloat(s)
        return isNaN(v) ? 0 : Math.max(0, Math.min(1, v / 100))
    }

    // 4 строки Resources (DESIGN: «метка значение + сегм. полоса»); полоса живая
    // у cpu/mem (есть проценты), net/block — значение без заполнения
    readonly property var resRows: {
        const s = DockerMon.statsData
        if (!s) return []
        return [
            { label: "CPU",     value: s.cpuPerc,  frac: _pct(s.cpuPerc) },
            { label: "MEMORY",  value: s.memUsage, frac: _pct(s.memPerc) },
            { label: "NET I/O", value: s.netIO,    frac: 0 },
            { label: "BLOCK I/O", value: s.blockIO, frac: 0 }
        ]
    }

    // "0.0.0.0:8888->8888/tcp, [::]:8888->8888/tcp" → строки маппинга
    // (ipv6-дубликат одного маппинга схлопываем)
    readonly property var portRows: {
        const out = []
        const seen = {}
        if (!root.sel) return out
        const parts = root.sel.ports.split(", ")
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i]
            if (p.length === 0) continue
            const m = p.match(/^(\[?[^\]\s]*\]?):(\d+)->(\d+)\/(\w+)$/)
            if (m) {
                const key = m[2] + "->" + m[3] + "/" + m[4]
                if (seen[key]) continue          // [::]-дубль ipv4-маппинга
                seen[key] = true
                out.push({ host: m[1] + ":" + m[2],
                           target: m[3] + "/" + m[4] })
            } else {
                out.push({ host: "—", target: p })   // exposed без публикации
            }
        }
        return out
    }

    // порт для списка слева: первый опубликованный хост-порт либо ""
    function portOf(ports) {
        const m = ports.match(/:(\d+)->/)
        return m ? m[1] : ""
    }
}
