// ARCH·UI v2 — components/AgentChat.qml (SPEC §6, DESIGN §4 «chat»)
// Панель чата с агентом (слот C, panelId "chat"):
//   · лента: user — инверсия (invBg/invFg), bot — raise2, команды — строка
//     `▸ cmd` на raise, ошибки — инверсия (правило «ошибка»);
//   · стриминг дельт в текущий пузырь (батчинг в AgentBridge);
//   · typing-индикатор — 3 пульсирующие точки, пока generating и последний
//     пузырь ещё пуст;
//   · карточка agent question (extension_ui_request confirm/select/input) —
//     кнопками формата ответа, первая primary;
//   · поле kit/Field h40 + кнопка-стрелка; Enter — send, во время генерации
//     поле шлёт steer-очередь (AgentBridge.send сам ставит streamingBehavior).
// Head/foot живут в shell.qml (чип модели / чип треда / «+»).

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    readonly property int rowH: 30
    readonly property int fieldH: 40
    // максимальная ширина пузыря — ~78% ленты (pad панели уже срезан Panel.qml)
    readonly property real bubbleMaxW: width * 0.78

    // ---------------------------------------------------------------- лента
    Flickable {
        id: flick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputBar.top
        anchors.bottomMargin: 8
        clip: true
        contentHeight: feedCol.height
        contentWidth: width
        boundsBehavior: Flickable.StopAtBounds

        // автоскролл в хвост на росте ленты и на смене модели (стриминг)
        onContentHeightChanged: if (!root._userScrolled) flick.contentY = Math.max(0, flick.contentHeight - flick.height)
        onHeightChanged: if (!root._userScrolled) flick.contentY = Math.max(0, flick.contentHeight - flick.height)

        Column {
            id: feedCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            // пустое состояние
            Text {
                visible: AgentBridge.feed.length === 0
                anchors.left: parent.left
                anchors.leftMargin: 4
                text: "no conversation — say something"
                color: Theme.ghost
                font.family: Theme.font
                font.pixelSize: 10
            }

            Repeater {
                model: AgentBridge.feed

                delegate: Loader {
                    id: bubbleLoader
                    required property var modelData
                    readonly property var rec: modelData

                    anchors.left: parent.left
                    anchors.right: parent.right
                    // высота делегата = высота загруженного пузыря
                    height: item ? item.height : 0

                    sourceComponent: rec.kind === "user" ? userBubble
                                   : rec.kind === "cmd" ? cmdLine
                                   : rec.kind === "err" ? errLine
                                   : botBubble

                    Component {
                        id: userBubble
                        Rectangle {
                            id: userBubbleRect
                            readonly property var rec: bubbleLoader.rec
                            // недоставленное (rpc success=false / таймаут) — dim + маркер,
                            // НЕ удаляем (история важнее красоты; ревью M5)
                            readonly property bool failed: rec.failed === true
                            width: Math.min(bubbleMaxW,
                                            Math.max(contentText.implicitWidth, failMark.visible ? failMark.implicitWidth : 0) + 20)
                            height: contentText.implicitHeight + (failed ? 26 : 16)
                            anchors.right: parent.right
                            color: failed ? Theme.raise2 : Theme.invBg
                            opacity: failed ? 0.55 : 1
                            border.width: 0
                            radius: 2
                            Text {
                                id: contentText
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: failed ? 8 : 0
                                width: Math.min(bubbleMaxW - 20, implicitWidth)
                                wrapMode: Text.Wrap
                                text: rec.text
                                color: failed ? Theme.txt2 : Theme.invFg
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                            Text {
                                id: failMark
                                visible: userBubbleRect.failed
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                text: "✕ undelivered"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 8
                            }
                        }
                    }

                    Component {
                        id: botBubble
                        Rectangle {
                            readonly property var rec: bubbleLoader.rec
                            // пустой финализированный пузырь (ответ был только
                            // thinking/toolCalls) не рисуем
                            readonly property bool emptyDone: !rec.streaming && rec.text.length === 0
                            width: emptyDone ? 0 : Math.min(bubbleMaxW, contentText.implicitWidth + 20)
                            height: emptyDone ? 0
                                 : typingRow.visible ? typingRow.height + 12
                                                     : contentText.implicitHeight + 16
                            anchors.left: parent.left
                            visible: !emptyDone
                            color: Theme.raise2
                            border.width: 0
                            radius: 2

                            Text {
                                id: contentText
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                visible: rec.text.length > 0
                                wrapMode: Text.Wrap
                                text: rec.text + (rec.streaming ? "▌" : "")
                                color: Theme.txt
                                font.family: Theme.font
                                font.pixelSize: 11
                            }

                            // typing-индикатор: 3 пульсирующие точки (Motion.dotPulse),
                            // пока пузырь стримит, но текст ещё не пошёл
                            Row {
                                id: typingRow
                                visible: rec.streaming && rec.text.length === 0
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: Theme.txt2
                                        opacity: 0.25
                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            // фаза по индексу точки — волна
                                            PauseAnimation { duration: index * 160 }
                                            NumberAnimation { duration: Motion.dotPulse / 3; to: 1; easing.type: Easing.InOutSine }
                                            NumberAnimation { duration: Motion.dotPulse / 3; to: 0.25; easing.type: Easing.InOutSine }
                                            PauseAnimation { duration: Motion.dotPulse - 2 * (Motion.dotPulse / 3) - index * 160 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: cmdLine
                        Rectangle {
                            readonly property var rec: bubbleLoader.rec
                            width: cmdText.implicitWidth + 16
                            height: root.rowH - 8
                            anchors.left: parent.left
                            color: Theme.raise
                            border.width: 0
                            Text {
                                id: cmdText
                                anchors.centerIn: parent
                                text: rec.text
                                color: Theme.txt2
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                        }
                    }

                    Component {
                        id: errLine
                        Rectangle {
                            readonly property var rec: bubbleLoader.rec
                            width: Math.min(bubbleMaxW, errText.implicitWidth + 16)
                            height: errText.implicitHeight + 12
                            anchors.left: parent.left
                            // ошибка — инверсия (правило дизайн-системы)
                            color: Theme.invBg
                            border.width: 0
                            Text {
                                id: errText
                                anchors.centerIn: parent
                                width: Math.min(bubbleMaxW - 16, implicitWidth)
                                wrapMode: Text.Wrap
                                text: rec.text
                                color: Theme.invFg
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // died/ stopped: статус-строка + кнопка перезапуска ( SPEC §6 )
            Row {
                visible: AgentBridge.dead || AgentBridge.stopped
                anchors.left: parent.left
                anchors.leftMargin: 4
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentBridge.dead ? "agent process died — " + AgentBridge.statusText
                        : AgentBridge.stopped ? "agent stopped"
                        : ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10
                }
                Kit.Btn {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: AgentBridge.dead
                    text: "RESTART"
                    onClicked: AgentBridge.restart()
                }
            }
        }
    }

    // ручной скролл вверх отключает автоскролл до возврата в хвост
    property bool _userScrolled: false

    // ------------------------------------------------- карточка agent question
    Rectangle {
        id: questionCard
        visible: AgentBridge.question !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputBar.top
        height: qCol.implicitHeight + 20
        color: Theme.raise
        border.width: 1
        border.color: Theme.ghost

        Column {
            id: qCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
                text: AgentBridge.question ? AgentBridge.question.title : ""
                color: Theme.txt
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.Medium
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                visible: AgentBridge.question && AgentBridge.question.message.length > 0
                text: AgentBridge.question ? AgentBridge.question.message : ""
                color: Theme.txt2
                font.family: Theme.font
                font.pixelSize: 10
                wrapMode: Text.Wrap
                width: parent.width
            }
            Row {
                spacing: 8

                Repeater {
                    // confirm → [Yes/No], select → options, input/editor → Cancel
                    model: {
                        const q = AgentBridge.question
                        if (!q) return []
                        if (q.method === "confirm") return ["yes", "no"]
                        if (q.method === "select") return q.options
                        return ["cancel"]
                    }
                    delegate: Kit.Btn {
                        required property var modelData
                        required property int index
                        readonly property var q: AgentBridge.question
                        text: String(modelData).toUpperCase()
                        primary: index === 0
                        onClicked: {
                            if (!q) return
                            if (q.method === "confirm") AgentBridge.answerQuestion(modelData === "yes")
                            else if (modelData === "cancel") AgentBridge.answerQuestion(null)
                            else AgentBridge.answerQuestion(modelData)
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- поле + стрелка
    Row {
        id: inputBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 8

        Kit.Field {
            id: input
            width: parent.width - sendBtn.width - parent.spacing
            height: root.fieldH
            placeholder: {
                if (AgentBridge.dead || AgentBridge.stopped) return "agent offline…"
                if (AgentBridge.generating) return "generating — enter to steer…"
                return "message…"
            }
            onAccepted: {
                AgentBridge.send(text)
                input.text = ""
                root._userScrolled = false
                flick.contentY = Math.max(0, flick.contentHeight - flick.height)
            }
        }

        // кнопка-стрелка (DESIGN: «поле 40 с кнопкой-стрелкой»), ховер — инверсия
        Rectangle {
            id: sendBtn
            width: root.fieldH
            height: root.fieldH
            color: sendMa.containsMouse ? Theme.invBg : Theme.raise
            border.width: 0

            Kit.Icon {
                anchors.centerIn: parent
                name: "arrow-right"
                size: 14
                color: sendMa.containsMouse ? Theme.invFg : Theme.txt2
            }
            MouseArea {
                id: sendMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: input.accepted()
            }
        }
    }
}
