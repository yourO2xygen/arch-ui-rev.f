// ARCH·UI v2 — kit/Btn.qml (ANALYSIS: .btn — h 26, 500 10px; primary = белая заливка/
// чёрный текст; ховер — raise2 / у primary — лёгкий подъём заливки raise2)
//
// Использование:
//   import "../kit"
//   Btn { text: "NEW"; onClicked: … }
//   Btn { text: "KILL"; primary: true; onClicked: … }
//
// enabled: false → текст/заливка ghost, кликов нет (кнопки New/Kill, тулбары).

import QtQuick
import ".."

Rectangle {
    id: root

    property string text: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    readonly property bool hovered: ma.containsMouse && root.enabled

    implicitWidth: label.width + 16          // pad 8×2 по горизонтали (как Chip)
    implicitHeight: 26
    color: !root.enabled ? "transparent"
         : root.primary ? (root.hovered ? Theme.raise2 : Theme.invBg)
         : root.hovered ? Theme.raise2
         : Theme.raise

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: !root.enabled ? Theme.ghost
             : root.primary ? Theme.invFg
             : Theme.txt2
        font.family: Theme.font
        font.pixelSize: 10
        font.weight: Font.Medium
        font.letterSpacing: 1
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
