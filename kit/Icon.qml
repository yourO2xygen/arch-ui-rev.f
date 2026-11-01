// ARCH·UI v2 — kit/Icon.qml (SPEC §1, §8)
// Lucide-иконка → Shape/ShapePath (QtQuick.Shapes, retained-дерево, без перерастеризации —
// SPEC §8; НЕ Canvas).
//
// Использование:
//   import "../kit"
//   Icon { name: "cpu"; size: 14 }
//
// Данные — из синглтона IconData (FileView на assets/icons/icons.json, один инстанс на шелл).
// Stroke-правило (SPEC §3): stroke_vb = Theme.strokeE * 24 / size, пол 1.25 vb.
// Рендер: 24×24 логическое поле, масштаб size/24.

import QtQuick
import QtQuick.Shapes
import ".."
import "."

Item {
    id: root

    property string name: ""
    property real size: 14
    property color color: Theme.txt

    implicitWidth: size
    implicitHeight: size

    // внутреннее: готовая геометрия из IconData
    readonly property string _d: IconData.loaded && IconData.shapes.hasOwnProperty(name)
                                 ? IconData.shapes[name] : ""
    readonly property bool _found: _d.length > 0

    onNameChanged: _warnIfUnknown()
    Component.onCompleted: _warnIfUnknown()
    Connections {
        // warn и в случае, когда имя задано раньше загрузки icons.json
        target: IconData
        function onShapesChanged() { root._warnIfUnknown() }
    }

    function _warnIfUnknown() {
        if (name.length > 0 && IconData.loaded && !IconData.shapes.hasOwnProperty(name))
            console.warn(`[Icon] unknown icon: "${name}"`);
    }

    Shape {
        // Логическое поле 24×24, сжатое до size через scale (transformOrigin — верхний левый,
        // чтобы иконка не уезжала из layout-слота).
        width: 24
        height: 24
        transformOrigin: Item.TopLeft
        scale: root.size / 24
        visible: root._found
        asynchronous: false

        ShapePath {
            strokeColor: root.color
            strokeWidth: Math.max(1.25, Theme.strokeE * 24 / root.size)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root._d
            }
        }
    }
}
