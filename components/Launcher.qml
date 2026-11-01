// ARCH·UI v2 — components/Launcher.qml (SPEC §4, DESIGN §4 «launcher»)
// Лаунчер приложений (слот B, panelId "launcher", оверлей на всё окно слота —
// kit/Panel.overlay). Две стадии:
//   1 — dock 504×48 у нижней кромки слота (Kit.Field, placeholder «run…», каретка 9×2);
//   2 — список 504×372 растёт вверх от дока (Motion.launcherGrow 260ms, apple) по
//       первому символу или ↑↓. Строки h34: плитка-инициал 24, имя 11.5, категория
//       9 dim справа; выбранная — inset-маркер 2px. «no matches» — dim.
// Фильтр — подстрока (case-insensitive) по имени DesktopEntries (noDisplay=false).
// ↑↓ — циклическая навигация, Enter — вспышка строки + Quickshell.execDetached +
// закрытие лаунчера. Esc — закрыть. keyboardFocus Exclusive / HyprlandFocusGrab —
// в shell.qml (окно владеет свойствами).

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../kit" as Kit

Item {
    id: root

    readonly property int dockH: 48
    readonly property int listH: 372
    readonly property int rowH: Theme.hRowL
    readonly property int tileS: 24

    // ------------------------------------------------------------- приложения
    // DesktopEntries.applications.values — QObjectList всех записей; фильтруем
    // noDisplay и пустой exec, дальше обычная JS-фильтрация (модель маленькая).
    readonly property var _apps: DesktopEntries.applications.values

    property string query: ""
    property var results: []
    property int selected: 0

    // Стадия 2: первый символ ИЛИ навигация стрелками
    readonly property bool stage2: query.length > 0 || _arrowsUsed
    property bool _arrowsUsed: false

    // Вспышка запускаемой строки (индекс в results, -1 — нет)
    property int _flashIndex: -1

    onQueryChanged: root._refilter()
    on_AppsChanged: root._refilter()

    function _refilter() {
        const q = root.query.toLowerCase()
        const out = []
        const apps = root._apps
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            if (e.noDisplay || !e.execString) continue
            if (q.length > 0 && (e.name ? e.name : e.id).toLowerCase().indexOf(q) === -1)
                continue
            out.push(e)
        }
        out.sort((a, b) => {
            const an = (a.name ? a.name : a.id).toLowerCase()
            const bn = (b.name ? b.name : b.id).toLowerCase()
            return an < bn ? -1 : an > bn ? 1 : 0
        })
        root.results = out
        root.selected = 0
    }

    // Токенизация Exec= по desktop-entry-спеке: кавычки уважаются («--title "Hello
    // World"» → один аргумент), обратный слэш внутри кавычек экранирует; field codes
    // (%f/%F/%U/…, в т.ч. внутри токенов) вырезаются на этапе токенизации, %% → «%».
    // Результат — argv для execDetached(list).
    function _tokenizeExec(exec) {
        const argv = []
        let cur = "", quoted = false
        for (let i = 0; i < exec.length; i++) {
            const c = exec[i]
            if (quoted) {
                if (c === "\"") quoted = false
                else if (c === "\\" && i + 1 < exec.length) cur += exec[++i]
                else cur += c
            } else if (c === "\"") {
                quoted = true
            } else if (/\s/.test(c)) {
                if (cur.length > 0) { argv.push(cur); cur = "" }
            } else cur += c
        }
        if (cur.length > 0) argv.push(cur)

        const out = []
        for (let t = 0; t < argv.length; t++) {
            let s = "", i = 0
            const tok = argv[t]
            while (i < tok.length) {
                if (tok[i] === "%") {
                    if (tok[i + 1] === "%") { s += "%"; i += 2 }
                    else i += 2             // field code — вырезаем
                } else s += tok[i++]
            }
            if (s.length > 0) out.push(s)
        }
        return out
    }

    function _move(delta) {
        const n = root.results.length
        if (n === 0) return
        root.selected = ((root.selected + delta) % n + n) % n
        list.positionViewAtIndex(root.selected, ListView.Contain)
    }

    function _launch() {
        const e = root.results[root.selected]
        if (!e) return
        const argv = _tokenizeExec(e.execString)
        if (argv.length === 0) return
        root._flashIndex = root.selected
        // вспышка строки видна глазу — закрытие после неё
        flashTimer.restart()
        Quickshell.execDetached(argv)
    }

    function _close() {
        LayoutState.closeSlot("B")
    }

    Timer {
        id: flashTimer
        interval: Motion.glitchLite
        onTriggered: {
            root._flashIndex = -1
            // к моменту срабатывания слот могли заменить (launcher → чужое) —
            // закрываем только свой panelId
            if (LayoutState.slots.B === "launcher") root._close()
        }
    }

    // Эксклюзивный клавиатурный фокус окна (shell.qml) садится в поле лаунчера.
    Component.onCompleted: dock.input.forceActiveFocus()
    onVisibleChanged: if (visible) dock.input.forceActiveFocus()

    // ------------------------------------------------------------------ dock
    Kit.Field {
        id: dock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.dockH
        placeholder: "run…"
        caretW: 9
        fontPx: Theme.fs12

        onTextEdited: (t) => root.query = t
        onEscPressed: root._close()
        onAccepted: root._launch()
        onNavUp: { root._arrowsUsed = true; root._move(-1) }
        onNavDown: { root._arrowsUsed = true; root._move(1) }
    }

    // ------------------------------------------------------------------ список
    // Растёт вверх от дока: height 0 ↔ 372, Motion.launcherGrow apple.
    Item {
        id: listWrap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: dock.top
        height: root.stage2 ? root.listH : 0
        clip: true
        visible: height > 0

        Behavior on height {
            NumberAnimation {
                duration: Motion.launcherGrow
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.apple
            }
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.bottomMargin: 0
            model: root.results
            currentIndex: root.selected
            keyNavigationEnabled: false
            clip: true

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: root.rowH

                readonly property bool selected: index === root.selected
                readonly property bool flashing: index === root._flashIndex

                // Плитка-инициал 24 (иконки по дизайну не нужны)
                Rectangle {
                    id: tile
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.tileS
                    height: root.tileS
                    color: Theme.raise
                    border.width: 0

                    Text {
                        anchors.centerIn: parent
                        text: (row.modelData.name ? row.modelData.name : row.modelData.id).charAt(0).toUpperCase()
                        color: Theme.txt2
                        font.family: Theme.font
                        font.pixelSize: Theme.fs11
                        font.weight: Font.Medium
                    }
                }

                Text {
                    anchors.left: tile.right
                    anchors.leftMargin: 10
                    anchors.right: cat.visible ? cat.left : parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name ? row.modelData.name : row.modelData.id
                    color: Theme.txt
                    font.family: Theme.font
                    font.pixelSize: Theme.fs11   // DESIGN «11.5» — pixelSize int в Qt; округлено вниз
                    elide: Text.ElideRight
                }

                Text {
                    id: cat
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text.length > 0
                    text: row.modelData.genericName
                          ? row.modelData.genericName
                          : (row.modelData.categories && row.modelData.categories.length > 0
                             ? row.modelData.categories[0] : "")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                    elide: Text.ElideRight
                }

                // selected — inset-маркер 2px
                Rectangle {
                    x: 0
                    width: 2
                    height: parent.height
                    color: Theme.txt
                    visible: row.selected
                }

                // hover (клик мыши по строке тоже запускает)
                Rectangle {
                    anchors.fill: parent
                    color: Theme.raise
                    visible: hover.hovered && !row.selected
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        root.selected = row.index
                        root._launch()
                    }
                }

                // вспышка запуска
                Rectangle {
                    anchors.fill: parent
                    color: Theme.txt
                    opacity: 0
                    border.width: 0
                    SequentialAnimation on opacity {
                        running: row.flashing
                        NumberAnimation { to: 0.85; duration: Motion.flashIn }
                        NumberAnimation { to: 0; duration: Motion.glitchLite }
                    }
                }
            }

            // Пустой результат — «no matches» dim
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: root.results.length === 0
                text: "no matches"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fs11
            }
        }
    }


}
