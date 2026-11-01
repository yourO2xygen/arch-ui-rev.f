pragma Singleton
// ARCH·UI v2 — services/SysMon.qml (SPEC §4/§8)
//
// Живые значения системы для SysInfo (слот B):
//   cpu     — дельта /proc/stat между тиками (Timer 2s, idle+iowait), 0..1
//   mem     — /proc/meminfo MemTotal/MemAvailable, 0..1 (+ kB)
//   gpu/vram— ветки по вендору (одна на всю жизнь шелла):
//             nvidia → долгоживущий /usr/bin/nvidia-smi -l 5 (Process+SplitParser);
//             иначе скан /sys/class/drm/card[0-9]/device: vendor 0x1002 → amdgpu
//             sysfs (FileView watchChanges, темпа может не быть → gpuTemp 0),
//             vendor 0x8086 → intel name-only (у i915 метрик в sysfs нет);
//             ничего найдено нет → строки в UI — ghost.
//   battery — /sys/class/power_supply/BAT* (capacity/status, AC — ADP*/online)
//   network — /sys/class/net состояния + ip: Process `ip -brief addr` раз в 30s
//   uptime/loadavg — /proc/uptime, /proc/loadavg; host/kernel — /proc/sys/kernel/*
//
// Все значения — свойства для биндинга. Поллинг лёгкий и постоянный (/proc-чтения),
// gpu-поток один на процесс шелла; Component.onDestruction гасит nvidia-smi, чтобы
// перезагрузка конфига не плодила процессы.

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    // ------------------------------------------------------------------- cpu
    property real cpu: 0                       // 0..1
    readonly property int histLen: 32
    property var cpuHist: []                   // ring, новые в конце (спарклайн)

    // ------------------------------------------------------------------- mem
    property int memTotalKb: 0
    property int memAvailKb: 0
    readonly property int memUsedKb: Math.max(0, root.memTotalKb - root.memAvailKb)
    readonly property real mem: root.memTotalKb > 0 ? root.memUsedKb / root.memTotalKb : 0

    // ------------------------------------------------------------------- gpu
    // Вендор-ветвление (Task 13): выбор один раз при старте, ветки взаимоисключающие
    property bool gpuPresent: false
    property real gpu: 0                       // 0..1
    property int vramUsedMb: 0
    property int vramTotalMb: 0
    readonly property real vram: root.vramTotalMb > 0 ? root.vramUsedMb / root.vramTotalMb : 0
    property int gpuTemp: 0
    property bool _gpuDead: false
    property bool _nvidiaOk: false             // проба бинаря прошла
    property string _intelDriver: ""          // uevent amdgpu-скана, напр. "i915"
    readonly property string gpuName: root._amdCard.length > 0 ? "amdgpu"
                                 : root._nvidiaOk ? "nvidia"
                                 : root._intelDriver.length > 0 ? "intel igpu · " + root._intelDriver : ""
    property string gpuInfo: ""                // "name-only" — intel: имя есть, метрик нет
    property int _cardIdx: -1                  // скан /sys/class/drm/card[0-9] при старте
    property int _intelIdx: -1                 // первая card с vendor 0x8086
    property int _hwIdx: -1                    // скан hwmonX amdgpu (temp1_input опционален)
    property string _amdCard: ""               // базовый sysfs-путь amdgpu-карты

    // --------------------------------------------------------------- battery
    property bool batPresent: false
    property real battery: 0                   // 0..1
    property bool charging: false
    property bool onAc: false

    // --------------------------------------------------------------- network
    property string netIface: ""
    property string netIp: ""
    readonly property bool netUp: root.netIface.length > 0
    readonly property bool netWifi: root.netIface.indexOf("wl") === 0
    property bool vpnUp: false
    property string vpnIface: ""

    // ----------------------------------------------------------------- misc
    property bool btPresent: false
    property int usbCount: 0
    property double uptimeSec: 0
    property string loadavg: ""
    property string hostName: ""
    property string kernel: ""
    property string cpuModel: ""       // подпись метрики cpu (ANALYSIS 5.3: «ryzen 7 …»)

    FileView {
        path: "/proc/cpuinfo"
        watchChanges: false
        onLoaded: {
            const m = text().match(/^model name\s*:\s*(.+)$/m)
            if (m) root.cpuModel = m[1].replace(/\(R\)|\(TM\)|CPU\s|@.*$/g, "").replace(/\s+/g, " ").trim()
        }
    }

    // --------------------------------------------------------------- утилиты
    function fmtUptime(sec) {
        const d = Math.floor(sec / 86400)
        const h = Math.floor((sec % 86400) / 3600)
        const m = Math.floor((sec % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    function fmtKb(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + "G"
        if (kb >= 1024) return Math.round(kb / 1024) + "M"
        return kb + "K"
    }

    // -------------------------------------------------------------- cpu/mem тик
    // Δ/proc/stat: занятость = 1 − Δ(idle+iowait)/Δ(total). Первый сэмпл — база.
    property var _prevCpu: null

    function _parseStat(text) {
        const line = text.substring(0, text.indexOf("\n")).trim()   // строка "cpu  …"
        const p = line.split(/\s+/).slice(1)
        let total = 0
        const vals = []
        for (let i = 0; i < p.length; i++) { const v = +p[i]; vals.push(v); total += v }
        const idle = vals[3] + (vals.length > 4 ? vals[4] : 0)      // idle + iowait
        if (root._prevCpu !== null) {
            const dTotal = total - root._prevCpu.total
            const dIdle = idle - root._prevCpu.idle
            if (dTotal > 0)
                root.cpu = Math.max(0, Math.min(1, 1 - dIdle / dTotal))
            const hist = root.cpuHist.slice()
            hist.push(root.cpu)
            if (hist.length > root.histLen) hist.shift()
            root.cpuHist = hist
        }
        root._prevCpu = { total: total, idle: idle }
    }

    function _parseMeminfo(text) {
        const m = {}
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const c = lines[i].indexOf(":")
            if (c === -1) continue
            m[lines[i].substring(0, c)] = parseInt(lines[i].substring(c + 1).trim())
        }
        if (m.MemTotal > 0) root.memTotalKb = m.MemTotal
        if (m.MemAvailable > 0) root.memAvailKb = m.MemAvailable
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        watchChanges: false
        onLoaded: root._parseStat(text())
        onLoadFailed: e => console.warn("[SysMon] /proc/stat: " + e)
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        watchChanges: false
        onLoaded: root._parseMeminfo(text())
        onLoadFailed: e => console.warn("[SysMon] /proc/meminfo: " + e)
    }
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        watchChanges: false
        onLoaded: root.uptimeSec = parseFloat(text()) || 0
    }
    FileView {
        id: loadFile
        path: "/proc/loadavg"
        watchChanges: false
        onLoaded: root.loadavg = text().trim()
    }

    Timer {
        interval: 2000                             // SPEC §8: /proc-поллинг 2s
        running: true
        repeat: true
        onTriggered: {
            statFile.reload()
            memFile.reload()
            uptimeFile.reload()
            loadFile.reload()
            if (++root._slowTick >= 8) {           // ~16s — батарея/AC
                root._slowTick = 0
                batCapFile.reload()
                batStatFile.reload()
                acFile.reload()
            }
            if (++root._netTick >= 15) {           // ~30s — сеть (ip -brief)
                root._netTick = 0
                ipProc.exec(ipProc.command)
            }
        }
    }
    property int _slowTick: 7     // первый же тик — читаем батарею
    property int _netTick: 14     // и сеть

    // --------------------------------------------------------------- battery
    function _findSupply(kind) {
        // быстрый статический путь: BAT0/ADP1 у этой машины; порядок не критичен
        return kind === "bat" ? "/sys/class/power_supply/BAT0"
                              : "/sys/class/power_supply/ADP1"
    }

    FileView {
        id: batCapFile
        path: root._findSupply("bat") + "/capacity"
        watchChanges: false
        onLoaded: { root.batPresent = true; root.battery = Math.min(1, (parseInt(text()) || 0) / 100) }
        onLoadFailed: root.batPresent = false
    }
    FileView {
        id: batStatFile
        path: root._findSupply("bat") + "/status"
        watchChanges: false
        onLoaded: root.charging = text().trim() === "Charging"
        onLoadFailed: root.charging = false
    }
    FileView {
        id: acFile
        path: root._findSupply("ac") + "/online"
        watchChanges: false
        onLoaded: root.onAc = text().trim() === "1"
        onLoadFailed: root.onAc = false
    }

    // --------------------------------------------------------------- network
    // `ip -brief addr`: "wlan0  UP  192.168.1.103/24 …". Основной интерфейс — первый
    // физический UP с IPv4 (wl*/e*), виртуальные (lo/br-*/docker0/veth*) — мимо;
    // tun/tap/wg → vpn.
    Process {
        id: ipProc
        command: ["/usr/bin/ip", "-brief", "addr"]
        stdout: StdioCollector { id: ipOut; onStreamFinished: root._parseIp(ipOut.text) }
    }

    function _parseIp(text) {
        const lines = text.split("\n")
        let iface = "", ip = "", vpn = ""
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim().split(/\s+/)
            if (t.length < 2) continue
            const name = t[0].indexOf("@") !== -1 ? t[0].split("@")[0] : t[0]
            const up = t[1] === "UP"
            if (name === "lo") continue
            let v4 = ""
            for (let j = 2; j < t.length; j++)
                if (/^\d+\.\d+\.\d+\.\d+\//.test(t[j])) { v4 = t[j].split("/")[0]; break }
            if (/^(tun|tap|wg|vpn)/.test(name)) {
                if (up && !vpn) vpn = name
                continue
            }
            if (/^(br-|docker|veth|virbr|vif)/.test(name)) continue
            if (!iface && up && v4.length > 0) { iface = name; ip = v4 }
        }
        root.netIface = iface
        root.netIp = ip
        root.vpnIface = vpn
        root.vpnUp = vpn.length > 0
    }

    // ---------------------------------------------------------- bt/usb (медленно)
    Process {
        id: btProc
        command: ["/bin/sh", "-c", "ls /sys/class/bluetooth 2>/dev/null | head -1"]
        stdout: StdioCollector { id: btOut; onStreamFinished: root.btPresent = btOut.text.trim().length > 0 }
    }
    Process {
        id: usbProc
        command: ["/bin/sh", "-c", "ls /sys/bus/usb/devices 2>/dev/null | grep -c ':'"]
        stdout: StdioCollector { id: usbOut; onStreamFinished: root.usbCount = parseInt(usbOut.text.trim()) || 0 }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: { btProc.exec(btProc.command); usbProc.exec(usbProc.command) } }

    // ------------------------------------------------------------------- host
    FileView {
        path: "/proc/sys/kernel/hostname"
        watchChanges: false
        onLoaded: root.hostName = text().trim()
    }
    FileView {
        path: "/proc/sys/kernel/osrelease"
        watchChanges: false
        onLoaded: root.kernel = text().trim()
    }

    // ------------------------------------------------------------------- gpu
    // NVIDIA-ветка: один долгоживущий поток. Нет бинаря → FailedToStart, но QProcess
    // при этом НЕ эмитит exited — потому бинаря проверяем заранее FileView-пробой:
    // нет файла → _gpuDead навсегда и уходим в drm/sysfs-скан (amdgpu/intel ниже).
    property int _gpuLines: 0

    Process {
        id: gpuProc
        command: ["/usr/bin/nvidia-smi",
                  "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
                  "--format=csv,noheader,nounits", "-l", "5"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._parseGpu(data)
        }
        onExited: {
            // -l 5 сам не выходит: выход = мониторинг кончился → ghost (не замороженные
            // нули); рестарт не делаем — _gpuDead навсегда
            root._gpuDead = true
            root.gpuPresent = false
            if (root._gpuLines === 0)
                console.info("[SysMon] nvidia-smi завершился без строк — gpu/vram ghost")
            else
                console.warn("[SysMon] nvidia-smi завершился — gpu/vram ghost")
        }
        Component.onDestruction: if (gpuProc.running) gpuProc.signal(15)
    }

    // Проба бинаря: есть → nvidia-ветка (процесс), нет → drm-скан ниже.
    // FailedToStart у Process этого не покажет (см. комментарий у gpuProc).
    FileView {
        path: "/usr/bin/nvidia-smi"
        watchChanges: false
        onLoaded: { root._nvidiaOk = true; root.gpuPresent = true; gpuProc.exec(gpuProc.command) }
        onLoadFailed: {
            root._gpuDead = true
            root.gpuPresent = false
            console.info("[SysMon] nvidia-smi не найден — сканируем drm/sysfs-карты")
            root._cardIdx = 0
        }
    }

    // ------------------------------------------------- amdgpu / intel (sysfs)
    // Скан /sys/class/drm/card[0-9]/device/vendor (карты могут нумероваться не с
    // card0 — на i915-ноуте это card1): 0x1002 → amdgpu-карта (стоп), 0x8086 →
    // запомнить первый для intel-fallback, дальше по списку. printErrors: false —
    // отсутствующие cardN это норма скана, не шум в лог. Следующий шаг — через
    // Qt.callLater: смена path из handler'а дропает in-flight операцию FileView.
    FileView {
        id: cardScan
        printErrors: false
        path: root._cardIdx >= 0 && root._cardIdx <= 7
              ? "/sys/class/drm/card" + root._cardIdx + "/device/vendor" : ""
        watchChanges: false
        onLoaded: {
            const v = text().trim()
            if (v === "0x1002" && root._amdCard.length === 0) {
                root._amdCard = "/sys/class/drm/card" + root._cardIdx + "/device"
                root.gpuPresent = true
                root._hwIdx = 0                     // temp-файл ищем (может не быть)
                console.info("[SysMon] amdgpu card" + root._cardIdx + " — sysfs-метрики")
            } else {
                if (v === "0x8086" && root._intelIdx === -1) root._intelIdx = root._cardIdx
                Qt.callLater(root._scanAdvance)
            }
        }
        onLoadFailed: Qt.callLater(root._scanAdvance)
    }

    function _scanAdvance() {
        root._cardIdx++
        if (root._cardIdx > 7) root._scanDone()
    }

    function _intelActivate() {
        // name-only: метрик у iGPU в sysfs нет (gpu/vram = 0), UI рисует имя
        // вместо ghost; % / vram там — dim («iGPU», «shared»)
        if (root.gpuInfo.length > 0) return
        root.gpuPresent = true
        root.gpuInfo = "name-only"
        console.info("[SysMon] intel card" + root._intelIdx + " — name-only (метрик нет)")
    }

    function _scanDone() {
        // Скан прошёл без amdgpu: intel → name-only (если драйвер уже дочитан —
        // активируем, иначе это сделает uevent-FileView), ничего → ghost
        if (root._amdCard.length > 0) return
        if (root._intelIdx >= 0 && root._intelDriver.length > 0) root._intelActivate()
        else if (root._intelIdx === -1)
            console.info("[SysMon] gpu не найден — gpu/vram ghost")
    }

    // Драйвер intel-карты для gpuName (DRIVER=i915 в uevent)
    FileView {
        printErrors: false
        path: root._intelIdx >= 0
              ? "/sys/class/drm/card" + root._intelIdx + "/device/uevent" : ""
        watchChanges: false
        onLoaded: {
            const m = text().match(/^DRIVER=(\S+)$/m)
            if (m) root._intelDriver = m[1]
            if (root._cardIdx > 7 && root._amdCard.length === 0) root._scanDone()
        }
        onLoadFailed: if (root._cardIdx > 7) root._scanDone()
    }

    // AMD-метрики: только FileView + watchChanges (как battery/network, тик не
    // нужен). Путь появляется, когда скан нашёл карту; грузится он же — Process нет.
    FileView {
        printErrors: false
        path: root._amdCard.length > 0 ? root._amdCard + "/gpu_busy_percent" : ""
        watchChanges: root._amdCard.length > 0
        onLoaded: root.gpu = Math.max(0, Math.min(1, (parseInt(text()) || 0) / 100))
    }
    FileView {
        printErrors: false
        path: root._amdCard.length > 0 ? root._amdCard + "/mem_info_vram_used" : ""
        watchChanges: root._amdCard.length > 0
        onLoaded: root.vramUsedMb = Math.round((parseInt(text()) || 0) / 1048576)   // байты → MiB
    }
    FileView {
        printErrors: false
        path: root._amdCard.length > 0 ? root._amdCard + "/mem_info_vram_total" : ""
        watchChanges: root._amdCard.length > 0
        onLoaded: root.vramTotalMb = Math.round((parseInt(text()) || 0) / 1048576)
    }
    // Температура amdgpu: hwmonX перебором (первый существующий), файл может
    // отсутствовать вовсе → _hwIdx=-1, gpuTemp тихо 0. Шаг тоже через callLater.
    FileView {
        printErrors: false
        path: root._amdCard.length > 0 && root._hwIdx >= 0 && root._hwIdx <= 3
              ? root._amdCard + "/hwmon/hwmon" + root._hwIdx + "/temp1_input" : ""
        watchChanges: root._hwIdx === -2            // нашли — остаёмся live
        onLoaded: {
            root.gpuTemp = Math.round((parseInt(text()) || 0) / 1000)   // милли°C → °C
            root._hwIdx = -2
        }
        onLoadFailed: Qt.callLater(function advance() {
            if (root._hwIdx >= 0 && root._hwIdx < 3) root._hwIdx++
            else root._hwIdx = -1                   // temp нет — деградируем тихо
        })
    }

    function _parseGpu(line) {
        const t = line.trim().split(",")
        if (t.length < 4) return
        root._gpuLines++
        root.gpu = Math.max(0, Math.min(1, (+t[0] || 0) / 100))
        root.vramUsedMb = +t[1] || 0
        root.vramTotalMb = +t[2] || 0
        root.gpuTemp = +t[3] || 0
    }
}
