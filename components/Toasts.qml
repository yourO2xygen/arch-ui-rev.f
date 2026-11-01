// ARCH·UI v2 — components/Toasts.qml (SPEC §5, ANALYSIS §5.11)
// Стек тостов 276 top-right: ≤4 карточек (pad 12 13, плитка 32×32 raise2, title 600 11.5,
// body 10/1.4, время 9 dim, крестик виден всегда), critical — рамка txt и без таймаута,
// низ стека — свёртки «+N critical» и «+N» (спам), клик → NotifCenter.
//
// Ввод/маска окна живёт в shell.qml: маска — прямоугольник стека при наличии тостов,
// пустая при отсутствии (урок бара: от visible-факта, не от анимации).
//
// Появление — lite-вариант глича (Task 9): flicker + x-jitter ±2px + 2 инверсные
// полосы за Motion.glitchLite (200ms), БЕЗ шейдера — тосты частые, GPU не тратим.
//
// Использование (shell.qml): Toasts { id: toastsContent; anchors.fill: parent }
//   окно: implicitHeight: Math.max(1, toastsContent.contentHeight)

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    // геометрия для окна/маски
    readonly property real contentHeight: stackCol.height
    readonly property real contentWidth: 276

    readonly property var stack: NotifStore.toasts
    readonly property var pending: NotifStore.pendingCriticals
    readonly property int flood: NotifStore.floodCount

    // ------------------------------------------------------------- стек
    Column {
        id: stackCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Repeater {
            model: root.stack

            delegate: ToastCard {
                required property var modelData
                rec: modelData
            }
        }

        // «+N critical» — critical сверх стека (SPEC §5): клик → NotifCenter
        FoldCard {
            visible: root.pending.length > 0
            text: "+" + root.pending.length + " critical"
            onClicked: NotifStore.openCenter()
        }

        // «+N» — спам >10/3s (SPEC §5): клик → NotifCenter
        FoldCard {
            visible: root.flood > 0
            text: "+" + root.flood
            onClicked: NotifStore.openCenter()
        }
    }

    // ------------------------------------------------------------- карточка тоста
    component ToastCard: Rectangle {
        id: card

        property var rec: null
        readonly property bool critical: rec !== null && rec.urgency === 2
        // что рисовать в плитке: картинка / иконка темы / Lucide-fallback
        readonly property bool showImage: rec !== null && rec.iconUrl.length === 0
                                          && rec.image.length > 0
        readonly property bool showIcon: rec !== null && !showImage && rec.iconUrl.length > 0
                                         && NotifStore.themeIconOk(rec)
        readonly property bool showFallback: rec === null || (!showImage && !showIcon)

        width: parent.width
        height: cardCol.height + 24          // pad 12×2
        color: Theme.surface
        border.width: 1
        // critical — акцентная рамка (Theme без акцентных цветов: белая 1px)
        border.color: critical ? Theme.txt : Theme.raise2

        // появление: fade + slide 200 (lite-глич). rec.shown — только новые анимируют
        // (Repeater пересоздаёт делегаты при каждом изменении стека — показанные
        // карточки не должны мигать). ⚠ не binding: анимация на забинженом свойстве
        // по stop() отдаёт значение обратно биндингу (карточка вечно opacity 0).
        Component.onCompleted: {
            if (rec === null) return
            if (rec.shown) { opacity = 1; x = 0; return }
            rec.shown = true
            opacity = 0
            x = 12
            enterIn.restart()
        }
        // lite-глич: flicker + x-jitter + 2 инверсные полосы (монохром: Theme.txt)
        Rectangle {
            id: bandA
            anchors.left: parent.left
            anchors.right: parent.right
            y: parent.height * 0.22
            height: 2
            color: Theme.txt
            opacity: 0
            visible: opacity > 0
        }
        Rectangle {
            id: bandB
            anchors.left: parent.left
            anchors.right: parent.right
            y: parent.height * 0.58
            height: 2
            color: Theme.txt
            opacity: 0
            visible: opacity > 0
        }
        SequentialAnimation {
            id: enterIn
            // суммарно Motion.glitchLite (200ms); под-шаги — доли токена
            ParallelAnimation {
                SequentialAnimation {
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 60 }
                    NumberAnimation { target: card; property: "opacity"; to: 0.72; duration: 25 }
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 25 }
                }
                SequentialAnimation {
                    NumberAnimation { target: card; property: "x"; to: 0; duration: 60; easing.type: Easing.Bezier; easing.bezierCurve: Motion.apple }
                    NumberAnimation { target: card; property: "x"; to: -2; duration: 25 }
                    NumberAnimation { target: card; property: "x"; to: 2; duration: 25 }
                    NumberAnimation { target: card; property: "x"; to: 0; duration: 25 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 40 }
                    NumberAnimation { target: bandA; property: "opacity"; to: 0.9; duration: 30 }
                    NumberAnimation { target: bandA; property: "opacity"; to: 0; duration: 50 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 105 }
                    NumberAnimation { target: bandB; property: "opacity"; to: 0.9; duration: 30 }
                    NumberAnimation { target: bandB; property: "opacity"; to: 0; duration: 40 }
                }
            }
        }

        // hover — пауза таймера тоста (dunst mouse_hover)
        HoverHandler {
            onHoveredChanged: if (card.rec !== null) NotifStore.setPaused(card.rec, hovered)
        }

        Column {
            id: cardCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            anchors.rightMargin: 13
            anchors.leftMargin: 13
            spacing: 4

            Row {
                width: parent.width
                spacing: 11

                // плитка 32×32 raise2 + иконка 15
                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.raise2
                    anchors.verticalCenter: parent.verticalCenter

                    // настоящая картинка (image-data/file) → иконка темы → inbox (Lucide).
                    // rec.image при icon-name — «image://icon/<name>» (см. NotifStore.iconUrlOf):
                    // провайдер рендерит маджента-заглушку для отсутствующих имён, поэтому
                    // темные иконки проверяем hasThemeIcon и рисуем сами.
                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: card.showImage
                        source: visible ? card.rec.image : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        visible: card.showIcon
                        source: visible ? card.rec.iconUrl : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Kit.Icon {
                        anchors.centerIn: parent
                        size: 15
                        name: "inbox"
                        visible: card.showFallback
                        color: Theme.txt2
                    }
                }

                Column {
                    width: parent.width - 32 - 11 - 20   // минус плитка, gap и место крестика
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        visible: card.rec !== null && card.rec.summary.length > 0
                        text: visible ? card.rec.summary : ""
                        color: Theme.txt
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: card.rec !== null && card.rec.body.length > 0
                        // body-markup: StyledText (b/i/u); body клиентский — <a> не
                        // кликабелен (нет обработчика onLinkActivated), xss-поверхности нет
                        text: visible ? card.rec.body : ""
                        textFormat: Text.StyledText
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs10
                        lineHeight: 1.4
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                }
            }

            // кнопки действий (не default): у живых уведомлений
            Row {
                spacing: 6
                visible: card.rec !== null && card.rec.actions.length > 0
                         && card.rec.notif !== null

                Repeater {
                    model: card.rec !== null ? card.rec.actions : []

                    delegate: Kit.Chip {
                        required property var modelData
                        text: modelData.label
                        onClicked: NotifStore.invokeAction(card.rec, modelData.key)
                    }
                }
            }
        }

        // время + ×N — низ справа
        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 12
            anchors.rightMargin: 13
            anchors.bottomMargin: 10
            visible: card.rec !== null
            text: visible ? NotifStore.timeAgo(card.rec.time)
                          + (card.rec.dup > 1 ? " · ×" + card.rec.dup : "") : ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fs9
        }

        // крестик 12×12 — виден всегда (ANALYSIS §5.11), hover подсвечивает
        Item {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.rightMargin: 10
            width: 12
            height: 12

            Kit.Icon {
                anchors.centerIn: parent
                name: "x"
                size: 12
                color: xMa.containsMouse ? Theme.txt : Theme.dim
            }
            MouseArea {
                id: xMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (card.rec !== null) NotifStore.dismiss(card.rec)
            }
        }

        // клик по телу: default-действие или дисмис
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: card.rec !== null
            onClicked: NotifStore.activate(card.rec)
        }
    }

    // свёртка «+N» / «+N critical»
    component FoldCard: Rectangle {
        id: fold

        signal clicked()

        property string text: ""
        readonly property bool hovered: fMa.containsMouse

        width: parent.width
        height: 26
        color: fold.hovered ? Theme.raise2 : Theme.raise
        border.width: 1
        border.color: Theme.ghostLine

        Text {
            anchors.centerIn: parent
            text: fold.text
            color: Theme.txt2
            font.family: Theme.font
            font.pixelSize: Theme.fs10
            font.letterSpacing: 1
        }

        MouseArea {
            id: fMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fold.clicked()
        }
    }
}
