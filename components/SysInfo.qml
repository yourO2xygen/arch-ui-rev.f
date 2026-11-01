// ARCH·UI v2 — components/SysInfo.qml (SPEC §4, DESIGN §4 «sysinfo», ANALYSIS 5.3)
// Слот B (panelId "sysinfo"): метрики 2×2 (ячейка 228×92: значение 15 + юнит 9,
// подпись 9, сегментированная полоса; у cpu — спарклайн-гистограмма, fade-in столбца
// 200ms) + секция HARDWARE 2×3 (строки h28, метка-колонка 84, иконка 12): battery /
// network / vpn / bluetooth / usb + шестая строка по наличию железа (gpu °C, иначе
// loadavg). Нет nvidia-smi → gpu/vram — ghost-строки («—», dim). Все данные —
// биндинги на SysMon; панель сама ничего не читает (SPEC §8: чтения — в синглтоне).
// Head (i-gauge + SYSINFO + чип uptime) и foot (user@host · ядро) живут в shell.qml.

import QtQuick
import ".."
import "../kit" as Kit

Item {
    id: root

    property string panelId: ""

    readonly property bool gpuOk: SysMon.gpuPresent
    readonly property int sparkH: 14          // proto: спарклайн 14px (ANALYSIS 5.3)

    // ---------------------------------------------------------------- метрики
    // Ячейка 228×92: raise, pad 10/12, gap 6 (ANALYSIS 5.3 .metric)
    component Metric: Rectangle {
        id: cell

        property string label: ""
        property string value: ""
        property string unit: ""
        property string caption: ""
        property bool ghost: false            // ghost-ячейка: значение/подпись dim
        property real barValue: 0             // 0..1
        property bool spark: false            // спарклайн (только cpu)

        width: 228
        height: 92
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
                height: 10
                Text {
                    text: cell.label
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            Item {                             // значение 15 + юнит 9
                id: valRow
                width: parent.width
                height: 18
                Text {
                    id: valText
                    anchors.left: parent.left
                    anchors.baseline: parent.bottom
                    text: cell.value
                    color: cell.ghost ? Theme.dim : Theme.txt
                    font.family: Theme.font
                    font.pixelSize: 15
                }
                Text {
                    anchors.left: valText.right
                    anchors.leftMargin: 5
                    anchors.baseline: parent.bottom
                    text: cell.unit
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9
                }
            }

            Text {                             // подпись 9 dim (модель · °C …)
                width: parent.width
                text: cell.caption
                color: Theme.dim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 9
            }

            Kit.SegBar {
                width: parent.width
                value: cell.barValue
            }
        }

        // спарклайн-cpu — ВНЕ потока Column (R1): верхняя правая четверть ячейки,
        // рядом со значением. Гистограмма последних 12 значений cpuHist (proto:
        // 12 столбиков, h 14); новый столбик fade-in 200ms (Motion.sparkIn).
        Item {
            visible: cell.spark
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: valRow.verticalCenter
            width: 70                          // 12 × (4 + 2) − 2
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
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.sparkIn
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.apple
                        }
                    }
                    color: (SysMon.cpuHist[SysMon.cpuHist.length - parent.shown + index] || 0) >= 0.6
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
        property int metaW: 88
        property bool ghost: false            // нет железа/выключено — dim

        width: 228
        height: 28

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
            width: 64                         // метка-колонка 84 = 20 + 64
            text: hw.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9
            font.letterSpacing: 1
            elide: Text.ElideRight
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 84
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 84 - hw.metaW - 4
            text: hw.value
            color: hw.ghost ? Theme.dim : Theme.txt
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 11
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
            font.pixelSize: 9
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
                caption: SysMon.cpuModel.length > 0 ? SysMon.cpuModel : "cpu"
                barValue: SysMon.cpu
                spark: true
            }
            Metric {
                label: "MEMORY"
                value: (SysMon.memUsedKb / 1048576).toFixed(1)
                unit: "G used"
                caption: SysMon.fmtKb(SysMon.memAvailKb) + " available · " + SysMon.fmtKb(SysMon.memTotalKb) + " total"
                barValue: SysMon.mem
            }
            Metric {
                label: "GPU"
                value: root.gpuOk ? (SysMon.gpu * 100).toFixed(1) : "—"
                unit: root.gpuOk ? "%" : ""
                caption: root.gpuOk ? ("nvidia · " + SysMon.gpuTemp + "°") : "no gpu device"
                barValue: SysMon.gpu
                ghost: !root.gpuOk
            }
            Metric {
                label: "VRAM"
                value: root.gpuOk ? (SysMon.vramUsedMb >= 1024
                       ? (SysMon.vramUsedMb / 1024).toFixed(1) + " / " + (SysMon.vramTotalMb / 1024).toFixed(0)
                       : SysMon.vramUsedMb + " / " + SysMon.vramTotalMb) : "—"
                unit: root.gpuOk ? (SysMon.vramUsedMb >= 1024 ? "G" : "M") : ""
                caption: root.gpuOk ? "gpu memory" : "no gpu device"
                barValue: SysMon.vram
                ghost: !root.gpuOk
            }
        }

        Kit.Section {
            width: parent.width
            label: "Hardware"

            Grid {
                columns: 2
                columnSpacing: 16
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
                    metaW: 52
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
                // шестая ячейка 2×3 — по наличию железа: gpu °C, иначе loadavg
                HwRow {
                    icon: root.gpuOk ? "gpu" : "activity"
                    label: root.gpuOk ? "gpu temp" : "load"
                    value: root.gpuOk ? (SysMon.gpuTemp + "°")
                                      : (SysMon.loadavg.split(" ")[0] || "—")
                    meta: root.gpuOk ? "nvidia" : "1 min"
                    ghost: !root.gpuOk && SysMon.loadavg.length === 0
                }
            }
        }
    }
}
