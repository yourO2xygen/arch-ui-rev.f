pragma Singleton
// ARCH·UI v2 — services/AgentBridge.qml (SPEC §6, research/PI-BACKEND.md)
//
// Мост к `pi --mode rpc` (1.4.0): JSONL over stdio, long-lived подпроцесс.
//
// Фактический протокол (docs/rpc.md / rpc-commands.md / json.md версии 1.4.0):
//   → stdin  {"id":"req-N","type":"prompt","message":"…"}  (+ LF)
//   ← stdout {"id":"req-N","type":"response","command":"prompt","success":true,
//             "data":{"disposition":"started"}}            — ПРИЁМКА, не готовность
//   ← stdout события: agent_start → message_start/update/end → turn_end →
//     agent_end → (auto_retry_*) → agent_settled            — конец работы агента
//   стриминг: message_update.assistantMessageEvent.text_delta {contentIndex, delta}
//   инструменты: tool_execution_start {toolCallId, toolName, args}
//   extension-диалоги: {"type":"extension_ui_request","id","method":"confirm|select|
//     input|editor",...} → отвечаем {"type":"extension_ui_response","id",...}
//
// Жизненный цикл (рулинг T4/Important-3 — слот C может быть ЗАМЕНЁН):
//   ленив ТОЛЬКО процесс: объект-синглтон инстанцируется биндингами head/foot
//   слота C сразу при загрузке шелла; Process же стартует при первом
//   openIn(C, "chat"|"aimgr") (следим за LayoutState.slots.C);
//   · уход с обеих панелей процесс НЕ убивает — контекст разговора дороже
//     150–300MB резидентного Node (suspend у rpc-протокола нет — задокументировано);
//   · непредвиденная смерть (crash/kill снаружи) → died → статус в UI + restart();
//   · Kill (кнопка AgentMgr) — SIGTERM, осознанная остановка (без статуса ошибки).
//
// stdin-очередь: записи, сделанные до running/при закрытом stdin, копятся в _outQ
// и сливаются по started (урок: запись до running теряется).
//
// Батчинг ленты: дельты стриминга — ровно тот случай (паттерн NotifStore/ProcMon):
// мутация пузырей in-place + один slice() за кадр через Qt.callLater(_flush).

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    // ------------------------------------------------------------- параметры
    readonly property string piPath: "/home/gitgut/.pi/agent/bin/pi"
    // Минимальный профиль чата (проверено на 1.4.0, `pi --help`): без MCP,
    // расширений, скиллов, шаблонов, тем и AGENTS/CLAUDE-контекста. Сессия —
    // in-memory (SPEC Q3: + кнопка New thread).
    readonly property var baseArgs: [
        "--mode", "rpc", "--no-session", "--no-mcp", "--no-extensions",
        "--no-skills", "--no-prompt-templates", "--no-themes", "--no-context-files"
    ]
    // Переопределение провайдера/модели на старте ("" — дефолт settings.json,
    // сейчас eliza/glm-5-3). Нужно для тестов: endpoint eliza может быть недоступен.
    property string providerOverride: ""
    property string modelOverride: ""
    // Отладочный дамп ВСЕХ входящих записей (по умолчанию выключен — не спамим прод).
    property bool debugLog: false

    // ------------------------------------------------------------- состояние
    property bool connected: false        // процесс жив (running)
    property bool dead: false             // непредвиденная смерть (died) — статус + restart
    property bool stopped: false          // остановлен осознанно (Kill)
    property bool generating: false       // agent_start … agent_settled
    property string statusText: ""        // проходящая мета (retry 1/3, queued, …)
    property var currentModel: null       // {provider, id, name, contextWindow, …}
    property var models: []               // список get_available_models
    property var contextUsage: null       // {tokens, contextWindow, percent} | null
    property string sessionId: ""
    property int  messageCount: 0

    // Лента чата — живёт здесь (не в панели): replace chat↔aimgr не теряет разговор.
    // Элементы: {kind:"user"|"bot"|"cmd"|"err", text, streaming}
    property var feed: []

    // Открытый extension-диалог: {id, method, title, message, options} | null
    property var question: null

    // Готовность панели к «опросу» (ленивый синглтон: инстанс создаётся первым
    // чтением свойств из биндингов — старт следит за слотом C сам).
    readonly property bool slotCOurs: LayoutState.slots.C === "chat"
                                     || LayoutState.slots.C === "aimgr"

    onSlotCOursChanged: if (root.slotCOurs) root.ensureStarted()

    // ---------------------------------------------------------------- процесс
    function ensureStarted() {
        if (root.connected || root._starting) return
        root._starting = true
        root.dead = false
        root.stopped = false
        root.statusText = "starting…"

        // Урок T5: Process при FailedToStart НЕ эмитит exited — бинарь пробуем до старта.
        binProbe.path = root.piPath
        binProbe.reload()
    }

    FileView {
        id: binProbe
        watchChanges: false
        onLoaded: {
            if (!root._starting) return
            root._starting = false
            root._startProc()
        }
        onLoadFailed: (e) => {
            if (!root._starting) return
            root._starting = false
            root.dead = true
            root.statusText = "no pi binary"
            console.warn("[AgentBridge] " + root.piPath + " недоступен: " + e)
        }
    }

    function _startProc() {
        const args = [root.piPath].concat(root.baseArgs)
        if (root.providerOverride.length > 0) args.push("--provider", root.providerOverride)
        if (root.modelOverride.length > 0) args.push("--model", root.modelOverride)
        console.info("[AgentBridge] starting pi rpc: " + args.join(" "))
        piProc.exec(args)
    }

    Process {
        id: piProc

        // Строгий JSONL-фрейминг: резать ТОЛЬКО по "\n" (SplitParser, не readline —
        // U+2028/U+2029 валидны внутри JSON-строк; docs/rpc.md «Framing»).
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => root._onLine(data)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t.length > 0) console.warn("[AgentBridge] pi stderr: " + t.slice(0, 500))
            }
        }

        onStarted: {
            console.info("[AgentBridge] pi started")
            root.connected = true
            root.statusText = ""
            root._flushOutQ()
            // Подписка/синк до первого prompt (docs: subscribe before prompt).
            root._cmd({ type: "get_state" })
            root._cmd({ type: "get_available_models" })
            root._cmd({ type: "set_auto_compaction", enabled: true })
            root._cmd({ type: "get_session_stats" })
        }

        onExited: (code) => {
            console.warn("[AgentBridge] pi exited rc=" + code)
            root.connected = false
            root.generating = false
            // каретка/typing не должны мигать вечно в недобитом пузыре
            root._finishStreamingBubble()
            // открытая карточка question снимается: extension_ui_response не уедет
            // в свежий процесс после RESTART (рулинг ревью I1)
            root.question = null
            root._pending = {}          // ответы мёртвого процесса не приходят
            root._pendingAt = {}        // иначе sweep после RESTART снимет протухший
                                        // cb(null) → маркирует ЧУЖОЙ свежий пузырь
            // чужие записи мёртвого процесса не приедут в свежую сессию (M1)
            if (root._outQ.length > 0)
                console.warn("[AgentBridge] stdin-очередь сброшена при выходе: " + root._outQ.length)
            root._outQ = []
            if (root.stopped) {
                root.statusText = "stopped"
            } else {
                // непредвиденная смерть — died-статус в UI, поднимаем только по кнопке
                root.dead = true
                root.statusText = "died (rc " + code + ")"
                console.warn("[AgentBridge] pi умер (rc=" + code + ")")
            }
        }
        Component.onDestruction: if (piProc.running) piProc.signal(15)
    }

    // ---------------------------------------------------------------- stdout
    function _onLine(line) {
        const t = line.trim()
        if (t.length === 0) return
        let rec
        try { rec = JSON.parse(t) } catch (e) {
            // битая строка — в лог, не крэш
            console.warn("[AgentBridge] не-JSON строка: " + t.slice(0, 200))
            return
        }
        if (root.debugLog) console.info("[AgentBridge] <- " + t.slice(0, 300))
        switch (rec.type) {
        case "response":        root._onResponse(rec); break
        case "agent_start":     root.generating = true; break
        case "agent_settled":
            root.generating = false
            root.statusText = ""
            root._finishStreamingBubble()
            root._cmd({ type: "get_session_stats" })
            root._cmd({ type: "get_state" })
            break
        case "message_start":   root._onMessageStart(rec); break
        case "message_update":  root._onMessageUpdate(rec); break
        case "message_end":     root._onMessageEnd(rec); break
        case "tool_execution_start":
            root._push("cmd", "▸ " + rec.toolName + " " + root._argBrief(rec.args))
            break
        case "auto_retry_start":
            root.statusText = "retry " + rec.attempt + "/" + rec.maxAttempts + " — " + (rec.errorMessage || "")
            break
        case "auto_retry_end":
            if (rec.success === false) root._push("err", "error: " + (rec.finalError || "failed after retries"))
            root.statusText = ""
            break
        case "extension_ui_request": root._onExtUi(rec); break
        case "session_info_changed": break
        case "compaction_start": root.statusText = "compacting…"; break
        case "compaction_end":   root.statusText = ""; break
        }
    }

    function _onResponse(rec) {
        const cb = root._pending[rec.id]
        if (cb !== undefined) delete root._pending[rec.id]
        // иначе sweep снимет протухший _pendingAt → ложный "pending timeout"
        delete root._pendingAt[rec.id]
        if (rec.success && rec.data) {
            switch (rec.command) {
            case "get_state":
                root.currentModel = rec.data.model || null
                root.sessionId = rec.data.sessionId || ""
                root.messageCount = rec.data.messageCount || 0
                root.generating = !!rec.data.isStreaming
                break
            case "get_available_models":
                root.models = Array.isArray(rec.data.models) ? rec.data.models : []
                break
            case "get_session_stats":
                root.contextUsage = rec.data.contextUsage || null
                break
            }
        }
        if (cb) cb(rec)
        if (rec.success === false && rec.command !== "parse") {
            root._push("err", "rpc " + rec.command + ": " + (rec.error || "failed"))
        }
    }

    function _onMessageStart(rec) {
        const m = rec.message || {}
        if (m.role === "assistant") {
            root._botOpen = true
            root._push("bot", "", true)   // streaming bubble
        }
    }

    function _onMessageUpdate(rec) {
        const e = rec.assistantMessageEvent
        if (!e) return
        switch (e.type) {
        case "text_delta": {
            // append в текущий streaming-пузырь (in-place + один flush за кадр)
            const f = root.feed
            for (let i = f.length - 1; i >= 0; i--) {
                if (f[i].kind === "bot" && f[i].streaming) {
                    f[i].text += (e.delta || "")
                    root._queueFlush()
                    return
                }
            }
            root._push("bot", e.delta || "", true)
            break
        }
        case "error":
            root._push("err", e.errorMessage || e.delta || "stream error")
            break
        // thinking_delta/toolcall_* не рисуем — инструментальные события приходят
        // отдельными tool_execution_* записями (▸ cmd строки)
        }
    }

    function _onMessageEnd(rec) {
        const m = rec.message || {}
        if (m.role !== "assistant") return
        // авторитетный текст — финальное сообщение (docs: delta-only wire)
        let txt = ""
        const c = m.content
        if (Array.isArray(c)) {
            for (let i = 0; i < c.length; i++)
                if (c[i] && c[i].type === "text") txt += (c[i].text || "")
        } else if (typeof c === "string") txt = c
        const f = root.feed
        for (let i = f.length - 1; i >= 0; i--) {
            if (f[i].kind === "bot" && f[i].streaming) {
                f[i].text = txt.length > 0 ? txt : f[i].text
                f[i].streaming = false
                root._queueFlush()
                return
            }
        }
        if (m.errorMessage) root._push("err", m.errorMessage)
    }

    function _finishStreamingBubble() {
        const f = root.feed
        for (let i = f.length - 1; i >= 0; i--) {
            if (f[i].kind === "bot" && f[i].streaming) {
                if (f[i].text.length === 0) f[i].text = "—"
                f[i].streaming = false
                root._queueFlush()
            }
        }
    }

    // ------------------------------------------------------- extension dialogs
    function _onExtUi(rec) {
        if (rec.method === "notify") {
            root._push(rec.notifyType === "error" ? "err" : "cmd",
                       "» " + (rec.message || "notify"))
            return
        }
        // fire-and-forget прочие (setStatus/setWidget/…) — не рисуем
        if (rec.method !== "confirm" && rec.method !== "select"
            && rec.method !== "input" && rec.method !== "editor") return
        root.question = {
            id: rec.id, method: rec.method,
            title: rec.title || rec.method,
            message: rec.message || "",
            options: Array.isArray(rec.options) ? rec.options : []
        }
    }

    function answerQuestion(value) {
        const q = root.question
        if (!q) return
        root.question = null
        const resp = { type: "extension_ui_response", id: q.id }
        if (value === null) resp.cancelled = true
        else if (q.method === "confirm") resp.confirmed = !!value
        else resp.value = String(value)
        root._writeObj(resp)
    }

    // ------------------------------------------------------------------ stdin
    property var _outQ: []                // очередь записей (closed/старт)
    property var _pending: ({})           // id → callback(rec)
    property var _pendingAt: ({})         // id → Date.now() (sweep таймаута)
    // зависший (но живой) pi не должен вечно держать pending/статус (ревью M2)
    readonly property int pendingTimeoutMs: 30000
    property int _reqN: 0
    property bool _starting: false
    property bool _botOpen: false

    function _cmd(obj, cb) {
        const id = "req-" + (++root._reqN)
        obj.id = id
        if (cb) {
            root._pending[id] = cb
            root._pendingAt[id] = Date.now()
        }
        root._writeObj(obj)
    }

    // sweep: записи без ответа дольше pendingTimeoutMs — снимаем с warn
    Timer {
        interval: 5000
        running: root.connected
        repeat: true
        triggeredOnStart: false
        onTriggered: root._sweepPending()
    }

    function _sweepPending() {
        const now = Date.now()
        let dropped = 0
        let ids = ""
        for (const id in root._pendingAt) {
            if (now - root._pendingAt[id] > root.pendingTimeoutMs) {
                const cb = root._pending[id]
                delete root._pending[id]
                delete root._pendingAt[id]
                dropped++
                ids += " " + id
                if (cb) cb(null)       // rec=null — таймаут
            }
        }
        if (dropped > 0) {
            console.warn("[AgentBridge] pending timeout: " + dropped
                         + " запрос(ов) без ответа за " + root.pendingTimeoutMs + "ms; ids=" + ids)
            if (root.statusText.indexOf("queued") === 0) root.statusText = ""
        }
    }

    function _writeObj(obj) {
        const line = JSON.stringify(obj) + "\n"
        if (piProc.running) piProc.write(line)
        else {
            root._outQ.push(line)
            if (!root.connected && !root.dead && !root._starting) root.ensureStarted()
        }
    }

    function _flushOutQ() {
        while (root._outQ.length > 0 && piProc.running)
            piProc.write(root._outQ.shift())
    }

    // недоставленное сообщение (response success=false / таймаут) — маркируем
    // СВОЙ пузырь по ссылке из cb-замыкания, НЕ удаляем (история важнее
    // красоты; ревью M5/раунд 2 — привязка к конкретному запросу)
    function _markFailed(rec) {
        rec.failed = true
        root._queueFlush()
    }

    // ---------------------------------------------------------------- public
    function send(text) {
        const t = String(text).trim()
        if (t.length === 0 || root.dead || root.stopped) return
        const mine = root._push("user", t)
        if (root.generating) {
            // docs: prompt во время стрима без streamingBehavior — ошибка
            root._cmd({ type: "prompt", message: t, streamingBehavior: "steer" },
                      (rec) => { if (rec === null || rec.success === false) root._markFailed(mine) })
            root.statusText = "queued (steer)"
        } else {
            root._cmd({ type: "prompt", message: t },
                      (rec) => { if (rec === null || rec.success === false) root._markFailed(mine) })
        }
    }

    function steer(text) {
        const t = String(text).trim()
        if (t.length === 0 || !root.generating) return
        const mine = root._push("user", t)
        root._cmd({ type: "steer", message: t },
                  (rec) => { if (rec === null || rec.success === false) root._markFailed(mine) })
    }

    function abort() {
        if (!root.generating) return
        root._cmd({ type: "abort" })
    }

    function setModel(provider, modelId) {
        root._cmd({ type: "set_model", provider: provider, modelId: modelId },
                  (rec) => { if (rec && rec.success) root._applyState() })
    }

    function newThread() {
        // in-memory сессия (SPEC Q3) — новая сессия тем же процессом + чистая лента
        root._cmd({ type: "new_session" }, (rec) => {
            if (!rec || !rec.success) return
            root.feed = []
            root.question = null
            root._cmd({ type: "get_state" })
            root._cmd({ type: "get_session_stats" })
            console.info("[AgentBridge] new session")
        })
    }

    function stats() {
        root._cmd({ type: "get_session_stats" }, (rec) => {
            if (rec && rec.success && rec.data) root.contextUsage = rec.data.contextUsage || null
        })
    }

    // Осознанная остановка (кнопка Kill в AgentMgr): SIGTERM. dead НЕ ставим.
    function kill() {
        if (!piProc.running) return
        root.stopped = true
        if (root.generating) root._cmd({ type: "abort" })
        piProc.signal(15)
    }

    function restart() {
        root.dead = false
        root.stopped = false
        root.ensureStarted()
    }

    function _applyState() { root._cmd({ type: "get_state" }) }

    // ------------------------------------------------------------------ лента
    function _push(kind, text, streaming) {
        const rec = { kind: kind, text: text, streaming: !!streaming }
        root.feed.push(rec)
        root._queueFlush()
        return rec
    }

    // Батчинг (паттерн NotifStore): мутации in-place, вью — один slice() за кадр.
    property bool _dFeed: false
    property bool _flushQueued: false

    function _queueFlush() {
        root._dFeed = true
        if (root._flushQueued) return
        root._flushQueued = true
        Qt.callLater(root._flush)
    }

    function _flush() {
        root._flushQueued = false
        if (root._dFeed) { root._dFeed = false; root.feed = root.feed.slice() }
    }

    function _argBrief(args) {
        if (!args) return ""
        if (typeof args === "string") return args.slice(0, 60)
        const s = args.command || args.file_path || args.path || args.pattern || ""
        if (s.length > 0) return String(s).slice(0, 60)
        try { return JSON.stringify(args).slice(0, 60) } catch (e) { return "" }
    }
}
