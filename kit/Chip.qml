// ARCH·UI v2 — kit/Chip.qml (ANALYSIS: .chip — 500 10px/1, pad 4×8)
// Чип-метка/кнопка: selected — инверсия (invBg/invFg), обычный — raise/txt2.
//
// Использование:
//   import "../kit"
//   Chip { text: "6 containers" }
//   Chip { text: "cpu"; selected: true; onClicked: … }

import QtQuick
import ".."

Rectangle {
    id: root

    property string text: ""
    property bool selected: false
    signal clicked()

    readonly property bool hovered: ma.containsMouse

    width: label.width + 16          // pad 4×8 → 8+8 горизонталь
    height: label.height + 8         // 4+4 вертикаль (10px текст → h 18)
    color: root.selected ? Theme.invBg
         : root.hovered ? Theme.raise2
         : Theme.raise

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Theme.invFg : Theme.txt2
        font.family: Theme.font
        font.pixelSize: 10
        font.weight: Font.Medium
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
