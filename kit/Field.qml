// ARCH·UI v2 — kit/Field.qml (ANALYSIS: поле ввода — фон raise, фокус raise2; каретка-
// подчёркивание 3×2 (Task 24: ширина 8px перекрывала глиф), blink Motion.caretBlink
// (1070) с паузой Motion.caretPause (900) после ввода). Переиспользуемое поле:
// лаунчер (Theme.hDock), фильтр taskmgr (implicitHeight = Theme.hRowL), чат (f(40)).
//
// Использование:
//   import "../kit"
//   Field { height: Theme.hDock; placeholder: "run…"; onAccepted: … }
//   Field { onTextEdited: … }
//
// Сигналы: textEdited(string), accepted() (Enter), escPressed() (Esc — наверх не пускаем).
// Фокус-индикация — сменой фона (QTBUG-137166: border.width: 0). Идущий blink живёт
// только при activeFocus (спящий лаунчер не жжёт кадры).

import QtQuick
import ".."

Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property int caretW: 3
    property int caretH: 2
    property real fontPx: Theme.fs11
    signal textEdited(string text)
    signal accepted()
    signal escPressed()
    signal navUp()   // ↑/↓ — потребителю (лаунчер: навигация списка); наверх не пускаем
    signal navDown()

    implicitHeight: Theme.hRowL
    color: input.activeFocus ? Theme.raise2 : Theme.raise
    border.width: 0

    // Внутреннее: видимость каретки управляется таймерами ниже; делегат зеркалит.
    property real _caretOn: 1

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.txt
        selectionColor: Theme.raise2
        selectedTextColor: Theme.txt
        clip: true
        font.family: Theme.font
        font.pixelSize: root.fontPx

        onTextEdited: {
            root.textEdited(text)
            root._typing()
        }
        onAccepted: root.accepted()
        onActiveFocusChanged: root._syncBlink()

        Keys.onEscapePressed: (event) => {
            event.accepted = true
            root.escPressed()
        }
        Keys.onUpPressed: (event) => {
            event.accepted = true
            root.navUp()
        }
        Keys.onDownPressed: (event) => {
            event.accepted = true
            root.navDown()
        }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: root.fontPx
        }

        cursorDelegate: Rectangle {
            width: root.caretW
            height: root.caretH
            color: Theme.txt
            opacity: root._caretOn ? 1 : 0
        }
    }

    // Ввод: каретка горит Motion.caretPause, затем возобновляется blink.
    // Blink — полупериодами Motion.caretBlink/2 (как было в inline-поле TaskMgr).
    Timer {
        id: pauseTimer
        interval: Motion.caretPause
        onTriggered: blink.restart()
    }

    SequentialAnimation {
        id: blink
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "_caretOn"; to: 0; duration: Motion.caretBlink / 2 }
        NumberAnimation { target: root; property: "_caretOn"; to: 1; duration: Motion.caretBlink / 2 }
    }

    function _typing() {
        blink.stop()
        _caretOn = true
        if (input.activeFocus) pauseTimer.restart()
    }

    function _syncBlink() {
        if (input.activeFocus) _typing()
        else {
            pauseTimer.stop()
            blink.stop()
            _caretOn = true
        }
    }
}
