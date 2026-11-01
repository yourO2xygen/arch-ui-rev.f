// ARCH·UI v2 — kit/Row.qml (ANALYSIS: .row — h28, 400 11px txt2 / .rt 500 11 txt /
// .meta 9 dim справа; selected — inset-контур, hover — raise)
//
// ⚠ Имя «Row» конфликтует с QtQuick.Row: в файлах, где нужен и layout-Row, и этот
// компонент, импортируйте kit с неймспейсом — `import "../kit" as Kit`.
//
// Использование:
//   import "../kit"
//   Row { label: "cpu"; value: "12%"; meta: "note"; dot: "on" }
//
// Свойства: label (500 11 txt), value (400 11 txt2), meta (9 dim справа),
// selected (inset-контур 1px на полях 2.5px, как радио .mrow), dot (""|on|idle|off → Dot).

import QtQuick
import ".."
import "." as Kit

Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string meta: ""
    property bool selected: false
    property string dot: ""          // "" | "on" | "idle" | "off"
    signal clicked()

    readonly property bool hovered: ma.containsMouse

    height: Theme.hRowS
    color: root.selected ? Theme.raise2 : root.hovered ? Theme.raise : "transparent"

    // selected inset: контур 1px на внутренних полях 2.5px (ANALYSIS .mrow)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2.5
        color: "transparent"
        border.width: root.selected ? 1 : 0
        border.color: Theme.txt
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: metaText.visible ? metaText.left : parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Kit.Dot {
            visible: root.dot.length > 0
            state: root.dot
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.label.length > 0
            text: root.label
            color: Theme.txt
            font.family: Theme.font
            font.pixelSize: Theme.fs11
            font.weight: Font.Medium
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.value.length > 0
            text: root.value
            color: Theme.txt2
            font.family: Theme.font
            font.pixelSize: Theme.fs11
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Text {
        id: metaText
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.meta.length > 0
        text: root.meta
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fs9
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
