// ARCH·UI v2 — kit/Section.qml
// Заголовок секции: 9px caps dim uppercase + контент (column, spacing 8).
//
// Использование:
//   import "../kit"
//   Section {
//       label: "Hardware"
//       Text { ... }   // произвольные дети — уходят в контентную колонку
//   }

import QtQuick
import ".."

Column {
    id: root

    property string label: ""
    default property alias content: contentCol.data

    spacing: 8

    Text {
        visible: root.label.length > 0
        text: root.label.toUpperCase()
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fs9
    }

    Column {
        id: contentCol
        spacing: 8
    }
}
