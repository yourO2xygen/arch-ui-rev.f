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
    property string logContainer: ""              // чей хвост открыт ("" — никто)
    // выбранный контейнер — в сервисе (не в панели): смена выбора = смена хвоста логов
    property string selected: ""
    onSelectedChanged: {
        if (root.selected.length > 0) {
            root.logs(root.selected)
            // статы прошлого контейнера не мигают: сброс до первого ответа
            if (root.tab === "resources") {
                root.statsData = null
                root.stats(root.selected)
            }
        } else {
            root._stopLogs(); root.logContainer = ""; root._logReset()
            root.statsData = null; root._statsContainer = ""
        }
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

    Component.onCompleted: uidProc.exec(uidProc.command)

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
    // молчащие стримы не умирают по SIGPIPE.
    //
    // СТРОГИЙ reap — kill только при ВСЕХ условиях (рулинг ревью T6):
    //   1. uid-гейт: viaSudo → uid==0, иначе uid==текущему юзеру;
    //   2. args НАЧИНАЕТСЯ с маркера (argv[0]=/usr/bin/docker + logs/events);
    //   3. родитель — НЕ процесс qs (свои живые стримы не трогаем);
    //   4. fd-чек: среди /proc/<pid>/fd/* есть symlink → docker.sock; readlink
    //      недоступен (root-овненный /proc, отказ sudo) → жертва ПРОПУСКАЕТСЯ.
    // Токены ps парсятся регексом /^\s*(\d+)\s+(\d+)\s+(\d+)\s(.*)$/ — никаких
    // indexOf по ppid.
    readonly property string _fdProbeOk: "__fdprobe_ok__"

    function _reapOrphans() {
        reapProc.exec(["/usr/bin/ps", "-eo", "uid,pid,ppid,args"])
    }

    Process {
        id: reapProc
        stdout: StdioCollector { id: reapOut; onStreamFinished: root._parseOrphans(reapOut.text) }
        stderr: StdioCollector {}
    }

    // текущий uid — для гейта в не-sudo режиме
    property string _uid: ""
    Process {
        id: uidProc
        command: ["/usr/bin/id", "-u"]
        stdout: StdioCollector { id: uidOut; onStreamFinished: root._uid = uidOut.text.trim() }
    }

    function _parseOrphans(text) {
        const lines = text.split("\n")
        // pid'ы процессов qs — их прямые дети живы, не наши
        const qsPids = {}
        const recs = []
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s(.*)$/)
            if (!m) continue
            if (/(^|\s)qs(-d)? -c /.test(m[4])) qsPids[m[2]] = true
            recs.push({ uid: m[1], pid: m[2], ppid: m[3], args: m[4] })
        }
        const needUid = root.viaSudo ? "0" : root._uid
        const candidates = []
        for (let k = 0; k < recs.length; k++) {
            const r = recs[k]
            const marked = r.args.startsWith(root.dockerPath + " logs --tail 200")
                        || r.args.startsWith(root.dockerPath + " events --format")
            if (!marked) continue
            if (r.uid !== needUid) continue
            if (qsPids[r.ppid]) continue                       // свой живой стрим
            candidates.push(r.pid)
        }
        if (candidates.length === 0) return
        console.info("[DockerMon] reap candidates (uid+args+ppid): " + candidates.join(","))
        root._reapQueue = candidates
        root._reapConfirmed = []
        root._reapNextFdCheck()
    }

    property var _reapQueue: []
    property var _reapConfirmed: []

    function _reapNextFdCheck() {
        if (root._reapQueue.length === 0) {
            root._reapKillConfirmed()
            return
        }
        const pid = root._reapQueue[0]
        // fd-чек: readlink /proc/<pid>/fd даёт «socket:[in-core inode]», он не
        // равен inode файла сокета — потому сверяем через ss -xp: локальный inode
        // сокета процесса должен быть peer-инодом строки с путём docker.sock.
        // Маркер в конце отличает «связи нет» от «/proc/ss не читаются»: во
        // втором случае жертва пропускается (kill вслепую недопустим).
        const script = "pid=" + pid + "\n"
            + "peers=$(ss -xp 2>/dev/null | grep docker[.]sock "
            + "| grep -oE 'docker[.]sock[[:space:]]+[0-9]+[[:space:]]+[*][[:space:]]+[0-9]+' "
            + "| grep -oE '[0-9]+$')\n"
            + "mine=$(ss -xp 2>/dev/null | grep \"pid=$pid,\" "
            + "| grep -oE '[*][[:space:]]+[0-9]+' | grep -oE '[0-9]+$')\n"
            + "for i in $mine; do echo \"$peers\" | grep -qx \"$i\" && echo MATCH; done\n"
            + "echo " + root._fdProbeOk + "\n"
        fdCheckProc.exec(root.viaSudo
            ? ["/usr/bin/sudo", "-n", "/bin/sh", "-c", script]
            : ["/bin/sh", "-c", script])
    }

    Process {
        id: fdCheckProc
        stdout: StdioCollector { id: fdOut; onStreamFinished: root._onFdCheck(fdOut.text) }
        stderr: StdioCollector {}
    }

    function _onFdCheck(out) {
        const pid = root._reapQueue.shift()
        if (out.indexOf(root._fdProbeOk) === -1) {
            console.warn("[DockerMon] reap: fd-проба " + pid + " недоступна — жертва пропущена")
        } else if (out.indexOf("MATCH") !== -1) {
            root._reapConfirmed.push(pid)
        }
        root._reapNextFdCheck()
    }

    function _reapKillConfirmed() {
        if (root._reapConfirmed.length === 0) return
        console.info("[DockerMon] reaping " + root._reapConfirmed.length
                     + " orphan docker stream(s): " + root._reapConfirmed.join(","))
        // системный kill, не docker kill; жертвы uid 0 (viaSudo) → через sudo -n
        orphanKill.exec((root.viaSudo
            ? ["/usr/bin/sudo", "-n", "/usr/bin/kill"]
            : ["/usr/bin/kill"]).concat(root._reapConfirmed))
    }

    Process {
        id: orphanKill
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.length > 0) console.warn("[DockerMon] reap kill stderr: " + t)
            }
        }
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
    // Модель строк: объекты строк стабильны (мутируем _logBuf in place — push/trim),
    // вью видят один slice() за кадр (паттерн ProcMon) — ScriptModel по objectProp
    // "seq" не пересоздаёт делегаты на burst.
    property var _logBuf: []                          // [{seq,ts,src,text,level}]
    property bool _logDirty: false
    property bool _logFlushQueued: false
    property int _logSeq: 0
    property string _logsPending: ""                  // контейнер, ждущий смерти старого хвоста

    readonly property ScriptModel logModel: ScriptModel {
        objectProp: "seq"
        values: root._logBuf
    }

    function _logReset() {
        root._logBuf = []
        root._logDirty = true
        root._queueLogFlush()
    }

    function logs(container) {
        if (container === root.logContainer && root._logsPending.length === 0) return
        root.logContainer = container
        root._logReset()
        if (logProc.running) {
            // старый хвост убить и ждать выхода: двух живых хвостов не бывает
            root._logsPending = container
            logProc.signal(15)
            return
        }
        root._startLogs()
    }

    function _startLogs() {
        if (!root.dockerPresent || !root.dockerVisible
            || root.logContainer.length === 0) return
        root._logsPending = ""
        logProc.exec(root._cmd(["logs", "--tail", "200", "-t", "-f", root.logContainer]))
    }
    function _stopLogs() {
        root._logsPending = ""
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
        onExited: {
            // отложенный рестарт: новый хвост стартует только после смерти старого
            if (root._logsPending.length > 0 && root.dockerVisible) root._startLogs()
        }
        Component.onDestruction: root._stopLogs()
    }

    function _onLogLine(line, src) {
        let ts = ""
        let text = line
        // `logs -t`: "2026-11-01T12:41:58.885845230Z …" → HH:MM:SS (без QLocale — урок T3)
        const m = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})[.\d]*(Z|[+-]\d{2}:\d{2})?\s(.*)$/)
        if (m) { ts = m[1].substring(11, 19); text = m[3] }
        const lv = /error|fatal/i.test(text) ? "error"
                 : /warn|warning/i.test(text) ? "warn" : ""
        root._logBuf.push({ seq: ++root._logSeq, ts: ts, src: src, text: text, level: lv })
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
            root._logBuf = root._logBuf.slice()          // одно уведомление вью за кадр
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
    property string _statsPending: ""                 // ждущий смерти предыдущего stats
    property bool _statsStale: false                  // ответ сигналенного процесса — мимо модели

    function stats(container) {
        if (container === root._statsContainer && root._statsPending.length === 0
            && root.statsData !== null) return
        root._statsContainer = container
        root._statsPending = container
        if (statsProc.running) {
            root._statsStale = true                   // прошлый ответ — запятнан (M9)
            statsProc.signal(15)
            return
        }
        root._startStats()
    }

    function _startStats() {
        if (!root.dockerPresent || !root.dockerVisible
            || root._statsContainer.length === 0) return
        root._statsPending = ""
        statsProc.exec(root._cmd(["stats", "--no-stream",
                                  "--format", "{{json .}}", root._statsContainer]))
    }

    Process {
        id: statsProc
        stdout: StdioCollector { id: statsOut; onStreamFinished: root._parseStats(statsOut.text) }
        stderr: StdioCollector {}
        onExited: {
            if (root._statsPending.length > 0 && root.dockerVisible) root._startStats()
        }
        Component.onDestruction: if (statsProc.running) statsProc.signal(15)
    }

    function _parseStats(text) {
        // ответ запятнанного (сигналенного SIGTERMом) процесса — чужие метрики
        // в statsData не попадают; ждущий запрос перезапускаем (M9)
        if (root._statsStale) {
            root._statsStale = false
            if (root._statsPending.length > 0 && root.dockerVisible) root._startStats()
            return
        }
        const line = text.split("\n").find(l => l.trim().length > 0)
        if (!line) {
            // гонка: сигнал 15 у предыдущего опроса — перезапустить отложенный
            if (root._statsPending.length > 0 && root.dockerVisible) root._startStats()
            return
        }
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
            root._eventsDead = false                   // одна повторная попытка на открытие
            root._startEvents()
            root._refresh()                            // свежий список на открытие
            if (root.logContainer.length > 0) root._startLogs()
        } else {
            root._stopEvents()
            root._stopLogs()
        }
    }
}
