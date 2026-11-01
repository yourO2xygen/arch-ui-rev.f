// ARCH·UI v2 — kit/Icon.qml (SPEC §1, §8)
// Lucide-иконка из assets/icons/icons.json → Shape/ShapePath (QtQuick.Shapes, retained-дерево,
// без перерастеризации — SPEC §8; НЕ Canvas).
//
// Использование:
//   import "../kit"
//   Icon { name: "cpu"; size: 14 }
//
// Stroke-правило (SPEC §3): stroke_vb = Theme.strokeE * 24 / size, пол 1.25 vb.
// Рендер: 24×24 viewBox, масштабирование Qt-масштабом size/24.
// Источник — FileView, читает icons.json один раз при старте инстанса (15KB, кэшируется ОС;
// asynchronous не нужен — SPEC task-1 Step 3).

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: root

    property string name: ""
    property real size: 14
    property color color: Theme.txt

    implicitWidth: size
    implicitHeight: size

    // внутреннее
    property string _d: ""
    property bool _found: false

    FileView {
        id: iconFile
        path: Quickshell.shellPath("assets/icons/icons.json")
        preload: true
        watchChanges: false
        onLoaded: root._resolve()
        onLoadFailed: err => console.warn(`[Icon] icons.json load failed (${err})`)
    }

    onNameChanged: root._resolve()

    function _resolve() {
        if (!iconFile.loaded || root.name.length === 0)
            return;
        const data = JSON.parse(iconFile.text());
        const parts = data[root.name];
        if (!parts) {
            console.warn(`[Icon] unknown icon: "${root.name}"`);
            root._found = false;
            root._d = "";
            return;
        }
        let d = "";
        for (let i = 0; i < parts.length; i++)
            d += _elemToPath(parts[i][0], parts[i][1]) + " ";
        root._d = d.trim();
        root._found = true;
    }

    // [tag, attrs] → SVG path "d" (path/line/polyline/rect/circle/ellipse из lucide)
    function _elemToPath(tag, a) {
        switch (tag) {
        case "path":
            return a.d;
        case "line":
            return `M ${a.x1} ${a.y1} L ${a.x2} ${a.y2}`;
        case "polyline": {
            const p = a.points.trim().split(/[\s,]+/);
            let d = `M ${p[0]} ${p[1]}`;
            for (let i = 2; i + 1 < p.length; i += 2)
                d += ` L ${p[i]} ${p[i + 1]}`;
            return d;
        }
        case "rect": {
            const x = +a.x, y = +a.y, w = +a.width, h = +a.height;
            // rx/ry по правилам SVG: одно из другого, кламп к половине стороны
            let rx = a.rx !== undefined ? +a.rx : (a.ry !== undefined ? +a.ry : 0);
            let ry = a.ry !== undefined ? +a.ry : rx;
            rx = Math.min(rx, w / 2);
            ry = Math.min(ry, h / 2);
            if (rx <= 0 || ry <= 0)
                return `M ${x} ${y} h ${w} v ${h} h ${-w} Z`;
            return `M ${x + rx} ${y} H ${x + w - rx} A ${rx} ${ry} 0 0 1 ${x + w} ${y + ry}`
                 + ` V ${y + h - ry} A ${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}`
                 + ` H ${x + rx} A ${rx} ${ry} 0 0 1 ${x} ${y + h - ry}`
                 + ` V ${y + ry} A ${rx} ${ry} 0 0 1 ${x + rx} ${y} Z`;
        }
        case "circle": {
            const cx = +a.cx, cy = +a.cy, r = +a.r;
            return `M ${cx - r} ${cy} A ${r} ${r} 0 1 0 ${cx + r} ${cy}`
                 + ` A ${r} ${r} 0 1 0 ${cx - r} ${cy} Z`;
        }
        case "ellipse": {
            const cx = +a.cx, cy = +a.cy, rx = +a.rx, ry = +a.ry;
            return `M ${cx - rx} ${cy} A ${rx} ${ry} 0 1 0 ${cx + rx} ${cy}`
                 + ` A ${rx} ${ry} 0 1 0 ${cx - rx} ${cy} Z`;
        }
        default:
            console.warn(`[Icon] unsupported tag: "${tag}"`);
            return "";
        }
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
