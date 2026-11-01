pragma Singleton
// ARCH·UI v2 — services/ProcMon.qml (SPEC §4/§8)
//
// Таблица процессов для TaskMgr (слот A): /usr/bin/ps -eo pid,comm:40,pcpu,rss,user
// --sort=-pcpu --no-headers раз в 2s, ТОЛЬКО пока taskmgr открыт в слоте A
// (LayoutState.slots.A — иначе поллинг спит). Процесс ps — одноразовый на тик
// (StdioCollector), не форк на каждый чих UI.
//
// kill(pid): Process `kill <pid>` (SIGTERM). Строка не исчезает сразу — флаг
// rec.killing гасит её фейдом Motion.killFade в UI, а из модели строка выпадает
// только когда следующий тик ps её не вернул («подтверждение исчезновением»).
// Если процесс пережил SIGTERM, флаг снимается через тик — строка возвращается.
//
// Батчинг мутаций (паттерн NotifStore): массив мутируется in-place, вью видят его
// одним slice() за кадр через Qt.callLater(_flush).

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    // ------------------------------------------------------------- параметры
    readonly property int tickMs: 2000
    readonly property string psPath: "/usr/bin/ps"
    readonly property string killPath: "/usr/bin/kill"

    // ------------------------------------------------------------- состояние
    property var procs: []               // raw: все процессы ps, новые не нужны — sort на месте
    property string filter: ""           // подстрока name/user/pid
    property string sortBy: "cpu"        // "cpu" | "mem" | "pid"

    readonly property bool taskmgrVisible: LayoutState.slots.A === "taskmgr"

    // Отфильтрованный/отсортированный список для UI (пересчёт на смене входов).
    readonly property var view: {
        const f = root.filter.toLowerCase()
        const out = []
        for (let i = 0; i < root.procs.length; i++) {
            const r = root.procs[i]
            if (f.length > 0
                && r.name.toLowerCase().indexOf(f) === -1
                && r.user.toLowerCase().indexOf(f) === -1
                && String(r.pid).indexOf(f) === -1) continue
            out.push(r)
        }
        if (root.sortBy === "mem") out.sort((a, b) => b.rss - a.rss)
        else if (root.sortBy === "pid") out.sort((a, b) => a.pid - b.pid)
        else out.sort((a, b) => b.cpu - a.cpu)
        return out
    }

    readonly property ScriptModel model: ScriptModel {
        objectProp: "pid"
        values: root.view
    }

    // ------------------------------------------------------------- батчинг
    property bool _dProcs: false
    property bool _flushQueued: false

    function _queueFlush() {
        if (root._flushQueued) return
        root._flushQueued = true
        Qt.callLater(root._flush)
    }

    function _flush() {
        root._flushQueued = false
        if (root._dProcs) { root._dProcs = false; root.procs = root.procs.slice() }
    }

    // ------------------------------------------------------------- поллинг
    Timer {
        interval: root.tickMs
        running: root.taskmgrVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: psProc.exec(psProc.command)
    }

    Process {
        id: psProc
        command: ["/usr/bin/ps", "-eo", "pid,comm:40,pcpu,rss,user", "--sort=-pcpu", "--no-headers"]
        stdout: StdioCollector { id: psOut; onStreamFinished: root._parse(psOut.text) }
    }

    function _parse(text) {
        const lines = text.split("\n")
        const now = Date.now()
        const seen = {}
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.length === 0) continue
            const t = line.trim().split(/\s+/)
            if (t.length < 5) continue
            // pid comm pcpu rss user (comm может содержать пробелы — собираем середину)
            const pid = parseInt(t[0])
            const user = t[t.length - 1]
            const rss = parseInt(t[t.length - 2])
            const cpu = parseFloat(t[t.length - 3])
            let name = ""
            for (let j = 1; j < t.length - 3; j++) name += (j > 1 ? " " : "") + t[j]
            if (!(pid > 0) || name.length === 0) continue
            seen[pid] = true

            const old = root._byPid[pid]
            let rec
            if (old) {
                rec = old
                rec.cpu = cpu; rec.rss = rss
                // SIGTERM не сработал и тик прошёл — строка возвращается
                if (rec.killing && now - rec.killAt > root.tickMs + 500) rec.killing = false
            } else {
                rec = { pid: pid, name: name, cpu: cpu, rss: rss, user: user,
                        killing: false, killAt: 0 }
                root._byPid[pid] = rec
            }
            out.push(rec)
        }
        // исчезнувшие — чистим из индекса
        for (const k in root._byPid) if (!seen[k]) delete root._byPid[k]
        root.procs = out           // полная замена раз в тик — один flush и так есть
        root._dProcs = false
    }

    property var _byPid: ({})

    // ------------------------------------------------------------- kill
    function kill(pid) {
        const rec = root._byPid[pid]
        if (rec) {
            if (killProc.running) {
                // одноразовый killProc ещё занят предыдущим вызовом: не теряем молча —
                // откатываем флаг (строка не должна фейдить без реального SIGTERM)
                rec.killing = false
                root._dProcs = true
                root._queueFlush()
                console.warn("[ProcMon] kill(" + pid + ") отложен: killProc занят")
                return
            }
            rec.killing = true
            rec.killAt = Date.now()
            root._dProcs = true
            root._queueFlush()
        }
        killProc.exec([root.killPath, String(pid)])
    }

    Process {
        id: killProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }
}
