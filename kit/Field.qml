// ARCH·UI v2 — kit/Field.qml (DESIGN REV.F «GRID-A2 · research §2 input»):
// НЕ пилюля — терминальная строка: промпт «›» ink 16px, ввод, «вдавленный» в
// волосяную линию ПОД строкой (idle 1px ghost → фокус 2px ink за 120ms apple —
// «фокус показывается линией, не свечением», никакого glow), placeholder dim caps
// с letterspacing («[query]»), block-caret мигает steps-подобно — резкое вкл/выкл,
// период 1.15s (полупериод 575 литералом из макета; Motion.qml не редактируем).
// Выделение текста — инверсия (REV.F: инверсия — единственный акцент).
//
// Использование (потребитель — Launcher, Task 24/25; каретка после ввода твёрдо
// горит Motion.caretPause (900), затем мигает; без activeFocus мигания нет —
// спящий лаунчер не жжёт кадры, сам TextInput прячет делегата):
//   import "../kit"
//   Field { height: Theme.hDock; placeholder: "[query]"; fontPx: Theme.fs12; onAccepted: … }
//
// Сигналы: textEdited(string), accepted() (Enter), escPressed() (Esc — наверх не пускаем),
//          navUp()/navDown() (↑/↓ — потребителю).

import QtQuick
import ".."

Item {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property real fontPx: Theme.fs12
    signal textEdited(string text)
    signal accepted()
    signal escPressed()
    signal navUp()   // ↑/↓ — потребителю (лаунчер: навигация списка); наверх не пускаем
    signal navDown()

    implicitHeight: Theme.hRowL

    // Внутреннее: видимость block-caret переключается таймером без анимации (steps).
    property bool _caretOn: true

    // Промпт «›» — терминальный знак ввода, ink той же высотой, что запрос
    Text {
        id: prompt
        anchors.left: parent.left
        anchors.leftMargin: Theme.s16
        anchors.bottom: input.bottom
        text: "›"
        color: Theme.txt
        font.family: Theme.font
        font.pixelSize: root.fontPx
        font.weight: Font.Bold
    }

    TextInput {
        id: input
        anchors.left: prompt.right
        anchors.leftMargin: Theme.s12
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.s8
        verticalAlignment: TextInput.AlignBottom
        color: Theme.txt
        // выделение — инверсным прямоугольником (макет ::selection)
        selectionColor: Theme.invBg
        selectedTextColor: Theme.invFg
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

        // Placeholder — dim caps letterspacing; виден только при пустом вводе
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            visible: input.text.length === 0
            text: root.placeholder
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fs11
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
        }

        // block-caret: при 16px шрифте ≈9×17 (0.56em × 1.06em макета, «.q::after»)
        cursorDelegate: Rectangle {
            width: Math.max(2, Math.round(root.fontPx * 0.56))
            height: Math.round(root.fontPx * 1.06)
            color: Theme.txt
            opacity: root._caretOn ? 1 : 0
        }
    }

    // Волосяная линия под строкой — вся индикация фокуса: idle 1px ghost,
    // фокус 2px ink (растёт вверх от кромки), 120ms apple.
    Rectangle {
        id: focusLine
        anchors.left: input.left
        anchors.leftMargin: -Theme.s6
        anchors.right: input.right
        anchors.rightMargin: -Theme.s6
        anchors.bottom: parent.bottom
        height: input.activeFocus ? 2 : 1
        color: input.activeFocus ? Theme.invBg : Theme.ghost

        Behavior on height {
            NumberAnimation {
                duration: Motion.hoverMs
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }
        Behavior on color {
            ColorAnimation { duration: Motion.hoverMs }
        }
    }

    // Ввод: каретка твёрдо горит Motion.caretPause, затем blink полупериодами 575
    // (1.15s steps(1) из макета; Motion.qml не трогаем — интервал литералом).
    Timer {
        id: pauseTimer
        interval: Motion.caretPause
        onTriggered: blinkTimer.start()
    }
    Timer {
        id: blinkTimer
        interval: 575
        repeat: true
        onTriggered: root._caretOn = !root._caretOn
    }

    function _typing() {
        blinkTimer.stop()
        _caretOn = true
        if (input.activeFocus) pauseTimer.restart()
    }

    function _syncBlink() {
        if (input.activeFocus) _typing()
        else {
            pauseTimer.stop()
            blinkTimer.stop()
            _caretOn = true
        }
    }
}
