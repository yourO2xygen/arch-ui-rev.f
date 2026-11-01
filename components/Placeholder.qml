// ARCH·UI v2 — components/Placeholder.qml
// Панель-заглушка: показывает имя панели в теле слота. Служит проверке хореографии
// слота (открытие / замена / закрытие) до реализации реальных компонентов (задачи 3/4).
// panelId назначается kit/Panel.qml сразу после загрузки Loader'а.

import QtQuick
import ".."
import "../kit"

Item {
    id: root

    property string panelId: ""

    Section {
        anchors.centerIn: parent
        label: root.panelId === "" ? "panel" : root.panelId

        Text {
            text: root.panelId === "" ? "PANEL" : root.panelId.toUpperCase()
            color: Theme.txt
            font.family: Theme.font
            font.pixelSize: Theme.fs13
            font.letterSpacing: 2
        }

        Text {
            text: "placeholder · реальный компонент — задача 3/4"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fs9
        }
    }
}
