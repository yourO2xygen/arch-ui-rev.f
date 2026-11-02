// ARCH·UI v2 — components/SysInfo.qml (SPEC §4, DESIGN §4 «sysinfo», ANALYSIS 5.3)
// Слот A (panelId "sysinfo"): метрики 2×2 (ячейка 228×92: значение 15 + юнит 9,
// подпись 9, сегментированная полоса; у cpu — спарклайн-гистограмма, fade-in столбца
// 200ms) + секция HARDWARE одноколоночная (Task 17, ради места при Theme.px>1;
// строки h28 во всю ширину body, метка-колонка wLabel, иконка 12): battery /
// network / vpn / bluetooth / usb + шестая строка по наличию железа (gpu °C, иначе
// loadavg). Значения краткие (Task 17): CPU-подпись — cpuModelShort («i5 1155G7»),
// memory — «used/total G». GPU по вендору: nvidia / amdgpu дают метрики; intel —
// name-only (gpuName вместо ghost, % / vram — dim «iGPU», «shared»); headless — ghost.
// Все данные — биндинги на SysMon; панель сама ничего не читает (SPEC §8: чтения — в синглтоне).
// Head (i-gauge + SYSINFO + чип uptime) и foot (user@host · ядро) живут в shell.qml.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    readonly property bool gpuOk: SysMon.gpuPresent
    readonly property bool nameOnly: SysMon.gpuInfo === "name-only"   // intel iGPU
    readonly property int sparkH: 14          // proto: спарклайн 14px (ANALYSIS 5.3)
    readonly property int bodyW: parent !== null ? parent.width : 472  // ширина body (Loader)
    // Ячейка метрики — Theme-производная (Task 24; было фикс 228×92): 2×f(228)+16
    // встаёт в body 493, высота f(96) вмещает label fs9 + значение fs15 + подпись.
    readonly property int cellW: Theme.f(228)
    readonly property int cellH: Theme.f(96)

    // ---------------------------------------------------------------- метрики
    // Ячейка cellW×cellH: raise, pad 10/12, gap 6 (ANALYSIS 5.3 .metric)
    component Metric: Rectangle {
        id: cell

        property string label: ""
        property string value: ""
        property string unit: ""
        property string caption: ""
        property bool ghost: false            // ghost-ячейка: значение/подпись dim
        property real barValue: 0             // 0..1
        property bool spark: false            // спарклайн (только cpu)

        width: root.cellW
        height: root.cellH
        color: Theme.raise
        border.width: 0

        Column {
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 6

            Item {                             // LABEL 9 caps dim
                width: parent.width
                height: Theme.f(13)
                Text {
                    text: cell.label
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                    font.letterSpacing: 1
                }
            }

            Item {                             // значение 15 + юнит 9
                id: valRow
                width: parent.width
                height: Theme.f(22)
                Text {
                    id: valText
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    text: cell.value
                    color: cell.ghost ? Theme.dim : Theme.txt
                    font.family: Theme.font
                    font.pixelSize: Theme.fs15
                }
                Text {
                    anchors.left: valText.right
                    anchors.leftMargin: 5
                    anchors.baseline: parent.bottom
                    text: cell.unit
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fs9
                }
            }

            Text {                             // подпись 9 dim (модель · °C …)
                width: parent.width
                text: cell.caption
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fs9
            }

            Kit.SegBar {
                width: parent.width
                value: cell.barValue
            }
        }

        // спарклайн-cpu — ВНЕ потока Column (R1): верхняя правая четверть ячейки,
        // рядом со значением. Гистограмма последних 12 значений cpuHist (proto:
        // 12 столбиков, h 14).
        Item {
            visible: cell.spark
            anchors.right: parent.right
            anchors.rightMargin: 12
            // valRow не родитель и не сиблинг (он в Column) — anchors на него дают
            // WARN «not a parent or sibling». Позиция детерминирована вёрсткой
            // Column: margin 10 + label f(13) + spacing 6 + (valRow f(22) − spark 14)/2.
            anchors.top: parent.top
            anchors.topMargin: 10 + Theme.f(13) + 6 + Math.round((Theme.f(22) - root.sparkH) / 2)
            width: Theme.f(70)                 // 12 × (4 + 2) − 2
            height: root.sparkH

            readonly property int shown: 12
            readonly property int barW: 4
            readonly property int gap: 2
            readonly property int filled: Math.min(shown, SysMon.cpuHist.length)

            // Прогрев (фикс ревью T5): пока в hist меньше 12 точек, показываем
            // ровно filled реальных столбиков (не читаем отрицательные индексы);
            // столбики прижаты вправо, чтобы контейнер «подрастал» влево.
            Repeater {
                model: parent.filled

                Rectangle {
                    required property int index
                    x: (parent.shown - parent.filled + index) * (parent.barW + parent.gap)
                    anchors.bottom: parent.bottom
                    width: parent.barW
                    height: Math.max(1, Math.round(
                        (SysMon.cpuHist[SysMon.cpuHist.length - parent.filled + index] || 0)
                        * root.sparkH))
                    // индексация цвета — та же формула, что у высоты (синхронизация
                    // фикс M6: раньше в прогреве читался отрицательный индекс)
                    color: (SysMon.cpuHist[SysMon.cpuHist.length - parent.filled + index] || 0) >= 0.6
                           ? Theme.txt : Theme.txt2
                }
            }
        }
    }

    // --------------------------------------------------------------- HARDWARE
    // Строка h28: иконка 12 + метка caps (колонка 84) + значение + мета справа
    component HwRow: Item {
        id: hw

        property string icon: ""
        property string label: ""
        property string value: ""
        property string meta: ""
        property int metaW: Theme.wLabel      // Task 24: токен вместо фикс 88
        property bool ghost: false            // нет железа/выключено — dim

        width: parent.width                    // Task 17: одноколоночный HARDWARE — во всю ширину
        height: Theme.hRowS

        Kit.Icon {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: hw.icon
            size: 12
            color: hw.ghost ? Theme.ghost : Theme.txt2
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 20            // иконка 12 + gap 8
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.wLabel - 20         // метка-колонка wLabel = 20 + (wLabel−20)
            text: hw.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fs9
            font.letterSpacing: 1
            elide: Text.ElideRight
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.wLabel
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.wLabel - hw.metaW - 4
            text: hw.value
            color: hw.ghost ? Theme.dim : Theme.txt
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fs11
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: hw.metaW
            text: hw.meta
            color: Theme.dim
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fs9
        }
    }

    // ------------------------------------------------------------------- body
    // Отступы body (12·16·16) даёт сам kit/Panel — здесь без своих margins
    Column {
        anchors.fill: parent
        spacing: 16

        Grid {                                // метрики 2×2, ячейка 228×92
            columns: 2
            columnSpacing: 16
            rowSpacing: 8

            Metric {
                label: "CPU"
                value: (SysMon.cpu * 100).toFixed(1)
                unit: "%"
                caption: SysMon.cpuModelShort.length > 0 ? SysMon.cpuModelShort
                        : SysMon.cpuModel.length > 0 ? SysMon.cpuModel : "cpu"
                barValue: SysMon.cpu
                spark: true
            }
            Metric {
                label: "MEMORY"
                value: (SysMon.memUsedKb / 1048576).toFixed(1)
                       + "/" + (SysMon.memTotalKb / 1048576).toFixed(1)
                unit: "G"
                caption: SysMon.fmtKb(SysMon.memAvailKb) + " available"
                barValue: SysMon.mem
            }
            // name-only (intel iGPU): вместо ghost-пустоты — символьные значения
            Metric {
                label: "GPU"
                value: !root.gpuOk ? "—" : root.nameOnly ? "iGPU" : (SysMon.gpu * 100).toFixed(1)
                unit: root.gpuOk && !root.nameOnly ? "%" : ""
                caption: root.gpuOk
                        ? (SysMon.gpuName + (SysMon.gpuTemp > 0 ? " · " + SysMon.gpuTemp + "°" : ""))
                        : "no gpu device"
                barValue: SysMon.gpu
                ghost: !root.gpuOk || root.nameOnly
            }
            Metric {
                label: "VRAM"
                value: !root.gpuOk || root.nameOnly ? "—"
                       : (SysMon.vramUsedMb >= 1024
                          ? (SysMon.vramUsedMb / 1024).toFixed(1) + " / " + (SysMon.vramTotalMb / 1024).toFixed(0)
                          : SysMon.vramUsedMb + " / " + SysMon.vramTotalMb)
                unit: root.gpuOk && !root.nameOnly ? (SysMon.vramUsedMb >= 1024 ? "G" : "M") : ""
                caption: !root.gpuOk ? "no gpu device"
                        : root.nameOnly ? "shared system memory" : "gpu memory"
                barValue: SysMon.vram
                ghost: !root.gpuOk || root.nameOnly
            }
        }

        Kit.Section {
            width: parent.width
            label: "Hardware"

            // HARDWARE — одна колонка во всю ширину body (Task 17): при px>1 шрифт
            // крупнее, двухколоночная сетка 228px не помещала значения.
            Grid {
                id: hwGrid
                columns: 1
                width: root.bodyW
                rowSpacing: 4

                HwRow {                       // battery (нет батареи — не место пустует)
                    visible: SysMon.batPresent
                    icon: SysMon.charging ? "battery-charging"
                         : SysMon.battery > 0.6 ? "battery-full"
                         : SysMon.battery > 0.25 ? "battery-medium" : "battery-low"
                    label: "battery"
                    value: Math.round(SysMon.battery * 100) + "%"
                    meta: SysMon.charging ? "charging" : SysMon.onAc ? "on ac" : "discharging"
                }
                HwRow {
                    icon: SysMon.netUp ? (SysMon.netWifi ? "wifi" : "network") : "wifi-off"
                    label: "network"
                    value: SysMon.netUp ? (SysMon.netIp.length > 0 ? SysMon.netIp : "up") : "off"
                    meta: SysMon.netUp ? (SysMon.netWifi ? "wifi" : "eth") : "down"
                    metaW: Theme.f(52)
                    ghost: !SysMon.netUp
                }
                HwRow {
                    icon: "shield"
                    label: "vpn"
                    value: SysMon.vpnUp ? SysMon.vpnIface : "off"
                    meta: SysMon.vpnUp ? "tunnel" : "no tunnel"
                    ghost: !SysMon.vpnUp
                }
                HwRow {
                    icon: SysMon.btPresent ? "bluetooth" : "bluetooth-off"
                    label: "bluetooth"
                    value: SysMon.btPresent ? "on" : "off"
                    meta: SysMon.btPresent ? "adapter" : "no adapter"
                    ghost: !SysMon.btPresent
                }
                HwRow {
                    icon: "usb"
                    label: "usb"
                    value: SysMon.usbCount > 0 ? SysMon.usbCount + " devices" : "none"
                    meta: "bus"
                    ghost: SysMon.usbCount === 0
                }
                // шестая строка — по наличию железа: gpu °C, иначе loadavg
                HwRow {
                    icon: root.gpuOk ? "gpu" : "activity"
                    label: root.gpuOk ? "gpu temp" : "load"
                    value: root.gpuOk ? (SysMon.gpuTemp > 0 ? SysMon.gpuTemp + "°" : "—")
                                      : (SysMon.loadavg.split(" ")[0] || "—")
                    meta: root.gpuOk ? SysMon.gpuName : "1 min"
                    ghost: !root.gpuOk && SysMon.loadavg.length === 0
                }
            }
        }
    }
}
