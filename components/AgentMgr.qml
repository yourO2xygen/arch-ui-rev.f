// ARCH·UI v2 — components/AgentMgr.qml (SPEC §6, DESIGN §4 «aimgr»)
// Менеджер агента (слот C, panelId "aimgr"):
//   · табы Active / History (активный — инверсия); History — заглушка:
//     сессия in-memory (SPEC Q3), rpc-списка прошлых сессий протокол не отдаёт;
//   · секция RUNNING: строка агента (Dot состояния, имя, модель · статус, время);
//   · секция MODELS: радио-строки из rpc get_available_models, выбранная —
//     белая + залитое радио; теги default (из settings.json)/local (models.json);
//   · кнопки New / Kill (kit/Btn): New = new_session, Kill = SIGTERM pi c
//     статусом в foot/head (restart — кнопка в AgentChat и в RUNNING при died);
//   · чип contextUsage (get_session_stats.contextUsage.percent) — в head (shell.qml).
// Head/foot живут в shell.qml.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""
    property string tab: "active"       // "active" | "history"

    readonly property int rowH: 30
    readonly property real colRadio: 20
    readonly property real colTime: 72
    // Row spacing 10 × 2 зазора — иначе правая колонка уезжает за край
    readonly property real colName: width - colRadio - colTime - 20

    // ------------------------------------------------------------ табы
    Row {
        id: tabs
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 8

        Kit.Chip {
            text: "ACTIVE"
            selected: root.tab === "active"
            onClicked: root.tab = "active"
        }
        Kit.Chip {
            text: "HISTORY"
            selected: root.tab === "history"
            onClicked: root.tab = "history"
        }
    }

    // ------------------------------------------------------------- ACTIVE
    Column {
        id: activeCol
        visible: root.tab === "active"
        anchors.top: tabs.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Text {
            text: "RUNNING"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        // строка агента: одна сессия — один long-lived pi (архитектура моста)
        Rectangle {
            width: parent.width
            height: root.rowH
            color: agentMa.containsMouse ? Theme.raise : "transparent"
            border.width: 0

            Row {
                anchors.fill: parent
                spacing: 10

                Item {
                    width: root.colRadio
                    height: root.rowH
                    Kit.Dot {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        state: AgentBridge.dead ? "off"
                             : AgentBridge.generating ? "on"
                             : "idle"
                    }
                }
                Text {
                    width: root.colName
                    height: root.rowH
                    text: "pi chat agent"
                    color: AgentBridge.connected ? Theme.txt : Theme.dim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    width: root.colTime
                    height: root.rowH
                    text: AgentBridge.dead ? "died"
                        : AgentBridge.generating ? "running"
                        : AgentBridge.connected ? "idle"
                        : AgentBridge.stopped ? "stopped"
                        : "down"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MouseArea {
                id: agentMa
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // died: перезапуск прямо из RUNNING (дубль кнопки AgentChat — осознанно:
        // mgr смотрят не открывая чат)
        Kit.Btn {
            visible: AgentBridge.dead
            text: "RESTART"
            onClicked: AgentBridge.restart()
        }

        // ------------------------------------------------------------ MODELS
        Item { width: 1; height: 6 }

        Text {
            text: "MODELS"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        // список может быть большим — фликable-зона
        Item {
            width: parent.width
            height: root._modelsHeight()

            Flickable {
                anchors.fill: parent
                clip: true
                contentHeight: modelsCol.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: modelsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 2

                    Repeater {
                        model: AgentBridge.models

                        delegate: Rectangle {
                            id: mrow
                            required property var modelData
                            readonly property bool sel: AgentBridge.currentModel
                                                        && AgentBridge.currentModel.provider === modelData.provider
                                                        && AgentBridge.currentModel.id === modelData.id
                            readonly property bool isDefault: root._isDefault(modelData)
                            readonly property bool hovered: mMa.containsMouse

                            width: parent.width
                            height: root.rowH
                            color: sel ? Theme.raise2
                                 : hovered ? Theme.raise
                                 : "transparent"
                            border.width: 0

                            Row {
                                anchors.fill: parent
                                spacing: 0

                                Item {
                                    width: root.colRadio
                                    height: root.rowH
                                    // радио: выбранная — залитая белая, иначе полая
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        width: 9
                                        height: 9
                                        radius: 4.5
                                        color: mrow.sel ? Theme.txt : "transparent"
                                        border.width: mrow.sel ? 0 : 1
                                        border.color: mrow.hovered ? Theme.txt2 : Theme.dim
                                    }
                                }
                                Text {
                                    width: root.colName
                                    height: root.rowH
                                    text: mrow.modelData.provider + " / " + mrow.modelData.name
                                    color: mrow.sel ? Theme.txt : Theme.txt2
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: mrow.sel ? Font.Medium : Font.Normal
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    width: root.colTime
                                    height: root.rowH
                                    text: (mrow.isDefault ? "default" : "local")
                                    color: mrow.isDefault ? Theme.txt : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            MouseArea {
                                id: mMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AgentBridge.setModel(mrow.modelData.provider, mrow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 6 }

        // ------------------------------------------------------------ New / Kill
        Row {
            width: parent.width
            spacing: 8

            Kit.Btn {
                width: (parent.width - parent.spacing) / 2
                text: "NEW"
                enabled: AgentBridge.connected
                onClicked: AgentBridge.newThread()
            }
            Kit.Btn {
                width: (parent.width - parent.spacing) / 2
                text: "KILL"
                primary: true
                enabled: AgentBridge.connected
                onClicked: AgentBridge.kill()
            }
        }

        Text {
            visible: AgentBridge.dead || AgentBridge.stopped
            text: AgentBridge.dead ? "process " + AgentBridge.statusText + " — RESTART to bring back"
                 : AgentBridge.stopped ? "process stopped by user — RESTART in chat or start a new one"
                 : ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    // ------------------------------------------------------------ HISTORY
    Column {
        visible: root.tab === "history"
        anchors.top: tabs.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Text {
            text: "SESSIONS"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
            font.letterSpacing: 1
        }
        Text {
            text: "single session (in-memory)"
            color: Theme.txt2
            font.family: Theme.font
            font.pixelSize: 11
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "chat runs with --no-session (SPEC Q3): history lives in this\n"
                + "panel until New. restart of the process starts an empty one."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
        }
    }

    function _modelsHeight() {
        // все строки, но не выше остатка панели (фликable на переполнении)
        return Math.max(1, Math.min(AgentBridge.models.length * (root.rowH + 2), 200))
    }

    // «default» — модель дефолта settings.json (провайдер из первого снапшота
    // get_state при старте); остальные помечаем «local». Точной rpc-метки нет.
    property string _defaultProvider: ""

    Connections {
        target: AgentBridge
        function onCurrentModelChanged() {
            if (root._defaultProvider.length === 0 && AgentBridge.currentModel)
                root._defaultProvider = AgentBridge.currentModel.provider || ""
        }
    }

    function _isDefault(m) {
        return _defaultProvider.length > 0 && m.provider === _defaultProvider
    }
}
