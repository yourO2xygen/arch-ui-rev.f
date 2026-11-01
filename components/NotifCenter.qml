// ARCH·UI v2 — components/NotifCenter.qml (SPEC §5, ANALYSIS §5.5)
// Панель истории уведомлений (слот C): секции TODAY/YESTERDAY/EARLIER (по локальной
// дате), строки h52 (плитка 32 + тексты + время), у записей с живым объектом — кнопки
// действий, у записей из JSONL — нет. DND → список .muted (opacity .3).
// DND-тумблер и Clear живут в head слота (shell.qml), статус dnd — в foot.
//
// Использование (shell.qml): body: Component { NotifCenter {} } — panelId назначает
// kit/Panel.qml.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    // ------------------------------------------------------------- группировка
    readonly property var groups: _group(NotifStore.historyList)

    function _group(list) {
        const now = new Date()
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const g = { today: [], yesterday: [], earlier: [] }
        for (let i = 0; i < list.length; i++) {
            const t = list[i].time
            if (t >= today) g.today.push(list[i])
            else if (t >= today - 86400000) g.yesterday.push(list[i])
            else g.earlier.push(list[i])
        }
        return g
    }

    readonly property bool empty: NotifStore.historyCount === 0

    // ------------------------------------------------------------- список
    Item {
        id: listWrap
        anchors.fill: parent

        // DND → .muted (ANALYSIS §5.5)
        opacity: NotifStore.dnd ? 0.3 : 1
        Behavior on opacity {
            NumberAnimation { duration: Motion.dndToggle; easing.type: Easing.Bezier; easing.bezierCurve: Motion.apple }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            contentHeight: listCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                Text {
                    visible: root.empty
                    text: "EMPTY"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                    font.letterSpacing: 1
                }

                Repeater {
                    model: ["today", "yesterday", "earlier"]

                    delegate: Column {
                        id: section
                        required property string modelData
                        readonly property var items: root.groups[modelData]
                        readonly property real dim:
                            modelData === "yesterday" ? 0.4 : modelData === "earlier" ? 0.3 : 1

                        visible: items.length > 0
                        width: parent.width
                        spacing: 2

                        Text {
                            text: parent.modelData.toUpperCase()
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fs9
                            font.letterSpacing: 1
                        }

                        Repeater {
                            model: section.items

                            delegate: NotifRow {
                                required property var modelData
                                rec: modelData
                                opacity: section.dim
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- строка истории
    component NotifRow: Rectangle {
        id: row

        property var rec: null
        readonly property var actions: rec !== null && rec.notif !== null ? rec.actions : []
        // что рисовать в плитке: картинка / иконка темы / Lucide-fallback
        readonly property bool showImage: rec !== null && rec.iconUrl.length === 0
                                          && rec.image.length > 0
        readonly property bool showIcon: rec !== null && !showImage && rec.iconUrl.length > 0
                                         && NotifStore.themeIconOk(rec)
        readonly property bool showFallback: rec === null || (!showImage && !showIcon)

        width: parent.width
        height: Math.max(52, rowCol.height + 10)
        color: rowMa.containsMouse ? Theme.raise : "transparent"

        Column {
            id: rowCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            spacing: 4

            Row {
                width: parent.width
                spacing: 10

                // плитка 32×32 raise2 + иконка 15
                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.raise
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: row.showImage
                        source: visible ? row.rec.image : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        visible: row.showIcon
                        source: visible ? row.rec.iconUrl : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Kit.Icon {
                        anchors.centerIn: parent
                        name: "inbox"
                        size: 15
                        color: Theme.txt2
                        visible: row.showFallback
                    }
                }

                Column {
                    width: parent.width - 32 - 10 - metaText.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        visible: row.rec !== null && row.rec.summary.length > 0
                        text: visible ? row.rec.summary : ""
                        color: Theme.txt
                        font.family: Theme.font
                        font.pixelSize: Theme.fs10
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: row.rec !== null && row.rec.body.length > 0
                        text: visible ? row.rec.body : ""
                        textFormat: Text.PlainText
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs9
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: metaText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.rec !== null
                    text: visible ? NotifStore.timeAgo(row.rec.time)
                                  + (row.rec.dup > 1 ? " · ×" + row.rec.dup : "") : ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
            }

            // кнопки действий — только у живых (залоченных) уведомлений
            Row {
                spacing: 6
                visible: row.actions.length > 0

                Repeater {
                    model: row.actions

                    delegate: Kit.Chip {
                        required property var modelData
                        text: modelData.label
                        onClicked: NotifStore.invokeAction(row.rec, modelData.key)
                    }
                }
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
