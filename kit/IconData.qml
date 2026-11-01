pragma Singleton
// ARCH·UI v2 — kit/IconData.qml
// Единственный на шелл источник иконок: FileView на assets/icons/icons.json + разобранная
// модель {name → path "d"}. kit/Icon.qml только потребляет готовые строки.
// Парсинг один раз при старте поколения (15KB), watchChanges выключен — набор иконок статичен.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool loaded: file.loaded
    readonly property string source: Quickshell.shellPath("assets/icons/icons.json")

    // name → SVG path "d" (все элементы иконки, сконвертированные _elemToPath)
    property var shapes: ({})

    FileView {
        id: file
        path: root.source
        preload: true
        watchChanges: false
        onLoaded: root._parse()
        onLoadFailed: err => console.warn(`[IconData] icons.json load failed (${err})`)
    }

    function _parse() {
        let data;
        try {
            data = JSON.parse(file.text());
        } catch (e) {
            console.warn(`[IconData] icons.json parse error: ${e}`);
            return;
        }
        const map = {};
        for (const nm in data) {
            const parts = data[nm];
            let d = "";
            for (let i = 0; i < parts.length; i++)
                d += _elemToPath(parts[i][0], parts[i][1]) + " ";
            map[nm] = d.trim();
        }
        root.shapes = map;
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
            console.warn(`[IconData] unsupported tag: "${tag}"`);
            return "";
        }
    }
}
