pragma Singleton
// ARCH·UI v2 — services/DockerMon.qml (SPEC §4/§5/§7, DESIGN §4 «docker»)
//
// Push-канал состояния docker для панели Docker (слот A):
//   events  — ОДИН долгоживущий `docker events --format '{{json .}}' --since <now>`
//             (Process + SplitParser "\n"); контейнерные действия (start/die/stop/
//             destroy/kill/health_status) помечают dirty → дебаунс-refresh 350ms.
//   refresh — одноразовый `docker ps -a --format '{{json .}}'` (StdioCollector).
//   logs(c) — `docker logs --tail 200 -t -f <c>`; при смене контейнера старый
//             Process убивается (утечка процессов недопустима). Строки — батчем
//             за кадр (паттерн ProcMon), cap 500.
//   stats(c)— `docker stats --no-stream --format '{{json .}}'` по требованию,
//             переопрос Timer 5s пока панель просит (statsRequested).
//   action  — одноразовый `docker <verb> <c>`; результат НЕ гадается —
//             подтверждается пришедшим событием (→ refresh).
//
// Доступ: бинарь пробуется FileView-пробой ДО запуска процессов (урок T5: Process
// при FailedToStart НЕ эмитит exited). Нет прав к сокету (exit code + "permission
// denied") → однократная проба `sudo -n docker version`; и та не прошла →
// ghost-состояние (ghostReason), повторных попыток нет.
//
// Поллинг/долгоживущие процессы — только при открытой панели (dockerVisible),
// образец: ProcMon running-биндинг. Component.onDestruction гасит потоки.

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    readonly property string dockerPath: "/usr/bin/docker"

    // --------------------------------------------------------------- состояние
    property bool dockerPresent: false
    property bool viaSudo: false                  // нет прав к сокету → sudo -n
    property string ghostReason: ""               // "" | "no docker binary" | "no permission"
    property string version: ""                   // Server.Version
    property var containers: []                   // [{id,name,image,state,status,ports,health}]
    property var logLines: []                     // [{ts,src,text,level: ""|"warn"|"error"}]
    property string logContainer: ""              // чей хвост открыт ("" — никто)
    // выбранный контейнер — в сервисе (не в панели): смена выбора = смена хвоста логов
    property string selected: ""
    onSelectedChanged: {
        if (root.selected.length > 0) root.logs(root.selected)
        else { root._stopLogs(); root.logContainer = ""; root.logLines = [] }
    }
    // активный таб панели: resources требует переопроса stats — потому в сервисе
    property string tab: "logs"                    // "logs" | "resources" | "ports"
    onTabChanged: {
        if (root.tab === "resources" && root.selected.length > 0)
            root.stats(root.selected)
    }
    property var statsData: null                      // {cpuPerc,memUsage,memPerc,netIO,blockIO,pids}
    // таб Resources открыт → таймер 5s переопроса stats активен
    readonly property bool statsRequested: root.tab === "resources"

    readonly property bool dockerVisible: LayoutState.slots.A === "docker"
    readonly property int runningCount: {
        let n = 0
        for (let i = 0; i < root.containers.length; i++)
            if (root.containers[i].state === "running") n++
        return n
    }
    readonly property int exitedCount: {
        let n = 0
        for (let i = 0; i < root.containers.length; i++)
            if (root.containers[i].state === "exited") n++
        return n
    }

    function _cmd(args) {
        return root.viaSudo
            ? ["/usr/bin/sudo", "-n", root.dockerPath].concat(args)
            : [root.dockerPath].concat(args)
    }

    // --------------------------------------------------------------- доступ
    // Проба бинаря: нет файла → ghost навсегда, процессы не дёргаем.
    FileView {
        path: root.dockerPath
        watchChanges: false
        onLoaded: versionProc.exec(versionProc.command)
        onLoadFailed: {
            root.ghostReason = "no docker binary"
            console.info("[DockerMon] /usr/bin/docker не найден — docker ghost")
        }
    }

    Process {
        id: versionProc
        command: [root.dockerPath, "version", "--format", "{{json .}}"]
        stdout: StdioCollector { id: versionOut }
        stderr: StdioCollector { id: versionErr }
        onExited: (code) => {
            if (code === 0) {
                root._accessGranted(versionOut.text)
                return
            }
            if (/permission denied/i.test(versionErr.text)) {
                // однократная проба через sudo -n (пароль спросить не выйдет — и не надо)
                sudoVersionProc.exec(sudoVersionProc.command)
            } else {
                root.ghostReason = "docker error"
                console.warn("[DockerMon] docker version rc=" + code + ": "
                             + versionErr.text.trim())
            }
        }
    }

    Process {
        id: sudoVersionProc
        command: ["/usr/bin/sudo", "-n", root.dockerPath,
                  "version", "--format", "{{json .}}"]
        stdout: StdioCollector { id: sudoVersionOut }
        stderr: StdioCollector { id: sudoVersionErr }
        onExited: (code) => {
            if (code === 0) {
                root.viaSudo = true
                root._accessGranted(sudoVersionOut.text)
            } else {
                root.ghostReason = "no permission"
                console.info("[DockerMon] нет доступа к docker socket (и sudo -n отклонён) — ghost")
            }
        }
    }

    function _accessGranted(versionJson) {
        try {
            const v = JSON.parse(versionJson)
            root.version = v.Server && v.Server.Version ? v.Server.Version : ""
        } catch (e) { root.version = "" }
        root.dockerPresent = true
        root.ghostReason = ""
        root._reapOrphans()
        root._refresh()                            // первичный список
        if (root.dockerVisible) root._startEvents()
    }

    // ---------------------------------------------------------- reap осиротевших
    // Жёсткое убиение демона (pkill/краш) оставляет стримы events/logs -f без
    // родителя: Component.onDestruction при внешнем SIGTERM не гарантирован, а
    // молчащие стримы не умирают по SIGPIPE. Осиротевший = наш маркер командной
    // строки и родитель — НЕ qs (systemd --user переприемляет к себе, ppid≠1).
    // Живые стримы текущего демона (ppid = pid qs) не трогаем.
    function _reapOrphans() {
        reapProc.exec(["/usr/bin/ps", "-eo", "pid,ppid,args"])
    }

    Process {
        id: reapProc
        stdout: StdioCollector { id: reapOut; onStreamFinished: root._parseOrphans(reapOut.text) }
        stderr: StdioCollector {}
    }

    function _parseOrphans(text) {
        const lines = text.split("\n")
        const recs = []                                  // {pid, ppid, args}
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim().split(/\s+/)
            if (t.length < 3) continue
            recs.push({
                pid: t[0],
                ppid: t[1],
                args: lines[i].substring(lines[i].indexOf(t[1]) + String(t[1]).length + 1)
            })
        }
        // pid'ы процессов qs — их прямые дети живы, не наши
        const qsPids = {}
        for (let j = 0; j < recs.length; j++)
            if (/^qs(-d)? -c /.test(recs[j].args) || /^qs -c /.test(recs[j].args))
                qsPids[recs[j].pid] = true
        const doomed = []
        for (let k = 0; k < recs.length; k++) {
            const r = recs[k]
            const ours = r.args.indexOf(root.dockerPath + " logs --tail 200") !== -1
                      || r.args.indexOf(root.dockerPath + " events --format") !== -1
            if (ours && !qsPids[r.ppid]) doomed.push(r.pid)
        }
        if (doomed.length > 0) {
            console.info("[DockerMon] reaping " + doomed.length + " orphan docker stream(s): "
                         + doomed.join(","))
            // системный kill, не docker kill: жертвы — root-процессы sudo → через sudo -n
            orphanKill.exec((root.viaSudo
                ? ["/usr/bin/sudo", "-n", "/usr/bin/kill"]
                : ["/usr/bin/kill"]).concat(doomed))
        }
    }

    Process {
        id: orphanKill
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    // --------------------------------------------------------------- events (push)
    // since = момент старта стрима: replay всей истории с epoch не нужен.
    property bool _eventsDead: false               // стрим умер сам → не рестартуем спамом

    function _startEvents() {
        if (!root.dockerPresent || root._eventsDead || eventsProc.running) return
        eventsProc.exec(root._cmd([
            "events", "--format", "{{json .}}",
            "--since", String(Math.floor(Date.now() / 1000))]))
    }
    function _stopEvents() {
        if (eventsProc.running) eventsProc.signal(15)
    }

    Process {
        id: eventsProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._parseEvent(data)
        }
        stderr: StdioCollector {}
        onExited: (code) => {
            // штатная остановка (signal 15 при закрытии панели/уничтожении) — не смерть
            if (!root.dockerVisible) return
            root._eventsDead = true
            console.warn("[DockerMon] docker events завершился (rc=" + code + ") — стрим остановлен")
        }
        Component.onDestruction: root._stopEvents()
    }

    function _parseEvent(line) {
        if (line.trim().length === 0) return
        let ev
        try { ev = JSON.parse(line) } catch (e) { return }
        if (ev.Type !== "container") return
        switch (ev.Action) {
        case "start": case "die": case "stop": case "destroy":
        case "kill": case "health_status": case "rename": case "update":
            root._scheduleRefresh()
        }
    }

    // --------------------------------------------------------------- refresh (debounce)
    property bool _refreshQueued: false
    function _scheduleRefresh() {
        if (root._refreshQueued) return
        root._refreshQueued = true
        refreshDebounce.restart()
    }
    Timer {
        id: refreshDebounce
        interval: 350
        onTriggered: { root._refreshQueued = false; root._refresh() }
    }

    function _refresh() {
        if (!root.dockerPresent) return
        psProc.exec(root._cmd(["ps", "-a", "--format", "{{json .}}"]))
    }

    Process {
        id: psProc
        stdout: StdioCollector { id: psOut; onStreamFinished: root._parsePs(psOut.text) }
        stderr: StdioCollector {}
        Component.onDestruction: if (psProc.running) psProc.signal(15)
    }

    function _parsePs(text) {
        const out = []
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length === 0) continue
            let c
            try { c = JSON.parse(lines[i]) } catch (e) { continue }
            out.push({
                id: c.ID || "",
                name: c.Names || "",
                image: c.Image || "",
                state: c.State || "unknown",       // running | exited | paused | created…
                status: c.Status || "",
                ports: c.Ports || "",
                health: c.HealthStatus || "none"
            })
        }
        // running сверху, внутри — по имени
        out.sort((a, b) => {
            const ra = a.state === "running" ? 0 : 1
            const rb = b.state === "running" ? 0 : 1
            return ra !== rb ? ra - rb : a.name.localeCompare(b.name)
        })
        root.containers = out
    }

    // --------------------------------------------------------------- logs (tail -f)
    property var _logBuf: []
    property bool _logDirty: false
    property bool _logFlushQueued: false

    function logs(container) {
        if (container === root.logContainer) return
        if (logProc.running) logProc.signal(15)     // старый хвост убить (утечка недопустима)
        root.logContainer = container
        root._logBuf = []
        root._logDirty = true
        root._queueLogFlush()
        if (root.dockerVisible) root._startLogs()
    }

    function _startLogs() {
        if (!root.dockerPresent || root.logContainer.length === 0) return
        logProc.exec(root._cmd(["logs", "--tail", "200", "-t", "-f", root.logContainer]))
    }
    function _stopLogs() {
        if (logProc.running) logProc.signal(15)
    }

    Process {
        id: logProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._onLogLine(data, "stdout")
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => root._onLogLine(data, "stderr")
        }
        Component.onDestruction: root._stopLogs()
    }

    function _onLogLine(line, src) {
        if (line.length === 0 && src !== "stderr") { /* пустые строки лога держим */ }
        let ts = ""
        let text = line
        // `logs -t`: "2026-11-01T12:41:58.885845230Z …" → HH:MM:SS (без QLocale — урок T3)
        const m = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})[.\d]*(Z|[+-]\d{2}:\d{2})?\s(.*)$/)
        if (m) { ts = m[1].substring(11, 19); text = m[3] }
        const lv = /error|fatal/i.test(text) ? "error"
                 : /warn|warning/i.test(text) ? "warn" : ""
        root._logBuf.push({ ts: ts, src: src, text: text, level: lv })
        if (root._logBuf.length > 500) root._logBuf.splice(0, root._logBuf.length - 500)
        root._logDirty = true
        root._queueLogFlush()
    }

    function _queueLogFlush() {
        if (root._logFlushQueued) return
        root._logFlushQueued = true
        Qt.callLater(root._flushLogs)
    }
    function _flushLogs() {
        root._logFlushQueued = false
        if (root._logDirty) {
            root._logDirty = false
            root.logLines = root._logBuf.slice()
        }
    }

    // --------------------------------------------------------------- stats (по требованию)
    Timer {
        interval: 5000
        running: root.dockerVisible && root.statsRequested && root.dockerPresent
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._statsContainer.length > 0 && !statsProc.running)
                statsProc.exec(root._cmd(["stats", "--no-stream",
                                          "--format", "{{json .}}", root._statsContainer]))
        }
    }
    // контейнер для статов панель задаёт отдельно (может не совпадать с logs)
    property string _statsContainer: ""

    function stats(container) {
        root._statsContainer = container
        if (!statsProc.running && root.dockerVisible && container.length > 0)
            statsProc.exec(root._cmd(["stats", "--no-stream",
                                      "--format", "{{json .}}", container]))
    }

    Process {
        id: statsProc
        stdout: StdioCollector { id: statsOut; onStreamFinished: root._parseStats(statsOut.text) }
        stderr: StdioCollector {}
        Component.onDestruction: if (statsProc.running) statsProc.signal(15)
    }

    function _parseStats(text) {
        const line = text.split("\n").find(l => l.trim().length > 0)
        if (!line) return
        let s
        try { s = JSON.parse(line) } catch (e) { return }
        root.statsData = {
            cpuPerc: s.CPUPerc || "—",
            memUsage: s.MemUsage || "—",
            memPerc: s.MemPerc || "0%",
            netIO: s.NetIO || "—",
            blockIO: s.BlockIO || "—",
            pids: s.PIDs || "—"
        }
    }

    // --------------------------------------------------------------- action
    function action(verb, container) {
        if (["start", "stop", "restart", "kill"].indexOf(verb) === -1) return
        if (actionProc.running) {
            console.warn("[DockerMon] action(" + verb + ") отложен: actionProc занят")
            return
        }
        actionProc.exec(root._cmd([verb, container]))
        // результат не гадаем: придёт событие в events-стрим → _scheduleRefresh
    }

    Process {
        id: actionProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.length > 0) console.warn("[DockerMon] action stderr: " + t)
            }
        }
    }

    // --------------------------------------------------------------- видимость панели
    onDockerVisibleChanged: {
        if (!root.dockerPresent) return
        if (root.dockerVisible) {
            root._startEvents()
            root._refresh()                            // свежий список на открытие
            if (root.logContainer.length > 0) root._startLogs()
        } else {
            root._stopEvents()
            root._stopLogs()
        }
    }
}
