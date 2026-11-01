pragma Singleton
// ARCH·UI v2 — services/NotifStore.qml (SPEC §5, research/NOTIFICATIONS.md)
//
// Полный notification daemon: NotificationServer (D-Bus org.freedesktop.Notifications)
// + стор тостов/истории + JSONL-персист ~/.cache/arch-ui/notifications.jsonl.
//
// Правила (SPEC §5):
//   · capabilities: actions, body, body-markup, icon-static, persistence — НЕ
//     body-images (строгий rowstride-парсер QS не обойти) / inline-reply / sound /
//     action-icons / body-hyperlinks.
//   · urgency: hints byte читается вручную, fallback NORMAL (не low — иначе «critical
//     ведёт себя как low», NOTIFICATIONS §4); expireTimeout — миллисекунды (доки врут).
//   · critical: не истекает сам (таймаут клиента игнорируется), пробивает DND,
//     не сворачивается спам-детектором; сверх стека — «+N critical» (pendingCriticals).
//   · тосты ≤4, таймаут клиента >0 — уважается, 0 — никогда, -1 — по urgency (5/8s).
//   · дубли (app,summary,body) → ×N; спам >10/3s → свёртка «+N» (floodCount).
//   · transient — никогда в истории и в JSONL.
//   · история: копия данных в JS-сторе (не trackedNotifications — теряются на reload),
//     JSONL TTL 7д, ≤200; Retainable.lock() только при наличии actions; у записей из
//     JSONL кнопок нет (объектов нет).
//   · keepOnReload: переигранные уведомления приходят тем же id — апдейт на месте,
//     дублей нет. После РЕСТАРТА id-пространство сервера начинается с 1 — записи из
//     JSONL помечены bootId = 0 и в replace/дедупе по id не участвуют (иначе чужой
//     replace-id угробит чужую запись, NOTIFICATIONS §9.1).
//
// Использование:
//   Toasts (архив:toasts) читает toasts/pendingCriticals/floodCount;
//   NotifCenter (слот C) читает history (ScriptModel); IPC archui dnd(on) →
//   LayoutState.setDnd → NotifStore.dnd.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import ".."

Singleton {
    id: root

    // ------------------------------------------------------------- параметры
    readonly property int maxToasts: 4
    readonly property int timeoutLow: 5000          // expireTimeout == -1 → по urgency
    readonly property int timeoutNormal: 8000
    readonly property int spamWindowMs: 3000        // спам >10/3s → «+N»
    readonly property int spamLimit: 10
    readonly property int historyLimit: 200
    readonly property double historyTtlMs: 7 * 24 * 3600 * 1000
    readonly property int freshMs: 60000            // «свежесть» записи истории для dup/replace

    // ------------------------------------------------------------- состояние
    property var toasts: []              // записи на экране, новые сверху
    property var pendingCriticals: []    // critical сверх стека → «+N critical»
    property int floodCount: 0           // спам-свёртка «+N»
    property double lastFloodAt: 0
    property var historyList: []         // новые первые; ≤ historyLimit
    readonly property int historyCount: historyList.length

    readonly property bool dnd: LayoutState.dnd

    readonly property bool showing: toasts.length > 0
                                    || pendingCriticals.length > 0
                                    || floodCount > 0

    // Готовая модель истории для ListView/Repeater.
    readonly property ScriptModel history: ScriptModel {
        objectProp: "uid"
        values: root.historyList
    }

    // id-пространство сервера живёт в процессе (NOTIFICATIONS §9.1): заменить по id
    // можно только записи этого процесса (bootId > 0), не записи из JSONL.
    property int bootId: 0
    property int _uidSeq: 0
    property bool _promoting: false     // реентрант-гейт _promotePending (M7)

    property var _spamLog: []            // времена приёма (мс) для спам-детектора

    // ------------------------------------------------------------- батчинг мутаций
    // Ревью T4: каскад синхронных мутаций моделей (Repeater/incubator внутри
    // binding-каскада) — вероятный источник QV4-сегфолта. Все мутации трёх массивов —
    // in-place; вью видят их ровно один раз за кадр через Qt.callLater(_flush).
    property bool _dToasts: false
    property bool _dPending: false
    property bool _dHistory: false
    property bool _flushQueued: false

    function _queueFlush() {
        if (root._flushQueued) return
        root._flushQueued = true
        Qt.callLater(root._flush)
    }

    function _flush() {
        root._flushQueued = false
        if (root._dToasts) { root._dToasts = false; root.toasts = root.toasts.slice() }
        if (root._dPending) { root._dPending = false; root.pendingCriticals = root.pendingCriticals.slice() }
        if (root._dHistory) { root._dHistory = false; root.historyList = root.historyList.slice() }
    }

    // ------------------------------------------------------------- сервер
    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true        // рендерим StyledText (b/i/u)
        actionsSupported: true
        imageSupported: true             // cap «icon-static»
        // НЕ заявляем: body-images, body-hyperlinks, bodyImages, inline-reply,
        // action-icons, sound (NOTIFICATIONS §3)

        onNotification: (notif) => {
            notif.tracked = true
            root.accept(notif)
        }
    }

    // ------------------------------------------------------------- публичное
    function accept(n) {
        const urg = _urgencyOf(n)
        const now = Date.now()

        // replace (replaces_id) / keepOnReload-переигрывание: тот же id → апдейт на месте.
        // Только текущий процесс: после рестарта чужой id может совпасть с записью JSONL.
        const byId = _findById(n.id)
        if (byId) {
            _rebind(byId, n, urg, now)
            return
        }

        // коалиция дублей (app, summary, body)
        const dup = _findDup(n.appName, n.summary, n.body)
        if (dup) {
            _coalesce(dup, n, now)
            return
        }

        const rec = _makeRec(n, urg, now)
        if (rec.locked) n.Retainable.lock()
        n.closed.connect(reason => root._onClosed(rec, reason))
        _connectLive(rec, n)
        _route(rec, now)
    }

    // hover над тостом — пауза таймера (dunst mouse_hover): остаток замораживается
    function setPaused(rec, paused) {
        if (rec.paused === paused) return
        const now = Date.now()
        if (paused) {
            rec.remain = rec.deadline > 0 ? Math.max(0, rec.deadline - now) : 0
            rec.paused = true
        } else {
            rec.paused = false
            if (rec.remain > 0) rec.deadline = now + rec.remain
        }
    }

    // клик по телу тоста: default-действие, иначе — дисмис
    function activate(rec) {
        if (rec.hasDefault && rec.notif !== null) {
            const a = _actionObj(rec, "default")
            if (a !== null) { a.invoke(); return }
        }
        dismiss(rec)
    }

    function invokeAction(rec, key) {
        if (rec.notif === null) return
        const a = _actionObj(rec, key)
        if (a !== null) a.invoke()      // quickshell: ActionInvoked + close если !resident
    }

    function dismiss(rec) {
        if (rec.notif !== null) rec.notif.dismiss()
        else _closeToast(rec)
    }

    // IPC archui dismissToasts
    function dismissAll() {
        const list = root.toasts.slice()
        for (let i = 0; i < list.length; i++) dismiss(list[i])
    }

    function clearHistory() {
        for (let i = 0; i < root.historyList.length; i++) _release(root.historyList[i])
        root.historyList.length = 0
        _touchHistory()
        _writeDisk()
        console.info("[archui] notif history cleared")
    }

    // «+N critical» / «+N» на тосте → центр
    function openCenter() {
        LayoutState.openIn("C", "notifcenter")
    }

    // `now` / `12m` / `1h` / `3d`
    function timeAgo(ts) {
        const s = Math.max(0, Math.floor((Date.now() - ts) / 1000))
        if (s < 60) return "now"
        const m = Math.floor(s / 60)
        if (m < 60) return m + "m"
        const h = Math.floor(m / 60)
        if (h < 24) return h + "h"
        return Math.floor(h / 24) + "d"
    }

    // transient: свойство QS + строковые/численные варианты хинта (некоторые клиенты
    // шлют «TRUE»/«TRANSIENT» as-is — ревью T4 minor 7)
    function _transientOf(n) {
        if (n.transient === true) return true
        const h = n.hints && n.hints["transient"] !== undefined ? n.hints["transient"] : null
        if (h === null) return false
        if (typeof h === "string") return h.toLowerCase() === "true" || h === "1"
        const v = Number(h)
        return !isNaN(v) && v !== 0
    }

    // notification.image при icon-name-иконке — это «image://icon/<name>» (fallback
    // самого QS на appIcon), не реальная картинка: рендер плейсхолдером-маджентой для
    // отсутствующих в теме имён. Разделяем: iconUrl (имя темы) vs настоящая картинка.
    function iconUrlOf(image) {
        return image !== null && image.indexOf("image://icon/") === 0 ? image : ""
    }

    // можно ли отрисовать иконку темы (для fallback-решения в UI)
    function themeIconOk(rec) {
        if (rec.icon.length > 0) return Quickshell.hasThemeIcon(rec.icon)
        if (rec.iconUrl.length > 0) return Quickshell.hasThemeIcon(rec.iconUrl.substring(13))
        return false
    }

    // ------------------------------------------------------------- приём
    // Urgency читаем сами из hints (byte) — конверсия QS может дать Low, fallback NORMAL.
    function _urgencyOf(n) {
        const v = n.hints && n.hints["urgency"] !== undefined ? Number(n.hints["urgency"]) : 1
        if (isNaN(v)) return 1
        return Math.max(0, Math.min(2, Math.floor(v)))
    }

    function _makeRec(n, urg, now) {
        const actions = []
        let hasDefault = false
        const list = n.actions || []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            // default не рисуем кнопкой (он на клике по телу); inline-reply не заявлен
            // capability'ями — некоторые клиенты шлют его вопреки (ревью T4 minor 6)
            if (a.identifier === "default") { hasDefault = true; continue }
            if (a.identifier === "inline-reply") continue
            actions.push({ key: a.identifier, label: a.text })
        }
        return {
            uid: ++root._uidSeq,
            bootId: root.bootId,
            id: n.id,
            appName: n.appName.length > 0 ? n.appName : "notify",
            icon: n.appIcon,
            image: n.image,
            iconUrl: root.iconUrlOf(n.image),
            summary: n.summary,
            body: n.body,
            urgency: urg,
            transient: root._transientOf(n),
            time: now,
            timeout: n.expireTimeout,   // мс (NOTIFICATIONS §4: доки врут про секунды)
            actions: actions,           // [{key,label}] без default
            hasDefault: hasDefault,
            actRefs: list,              // живые NotificationAction для invoke()
            dup: 1,
            state: "",                  // toast | pending | history
            notif: n,                   // живой объект или null (после destroy/release)
            locked: actions.length > 0 || hasDefault,
            paused: false,
            deadline: 0,
            remain: 0,
            shown: false
        }
    }

    function _rebind(rec, n, urg, now) {
        // replace: поля обновляются атомарно, счётчик дублей не трогаем, таймер перезапускается
        rec.icon = n.appIcon
        rec.image = n.image
        rec.iconUrl = root.iconUrlOf(n.image)
        rec.summary = n.summary
        rec.body = n.body
        rec.urgency = urg
        rec.timeout = n.expireTimeout
        rec.time = now
        rec.dup = 1
        _syncActions(rec, n)

        const wasLocked = rec.locked
        const oldNotif = rec.notif
        rec.notif = n
        rec.paused = false
        if (rec.locked) n.Retainable.lock()
        // гейт: при повторном _rebind того же объекта не вешаем второй closed-коннект
        // (двойной _onClosed на закрытии) — по образцу _liveConnected
        if (!rec._closedConnected) {
            rec._closedConnected = true
            n.closed.connect(reason => root._onClosed(rec, reason))
        }
        _connectLive(rec, n)

        if (rec.state === "toast") {
            rec.deadline = _deadlineFor(rec)
            _touchToasts()
        } else if (rec.state === "pending") {
            _touchPending()
        } else if (rec.state === "" ) {
            _route(rec, now)            // переигранное после reload, ещё не разложенное
        } else {
            _touchHistory()
        }
        if (wasLocked && oldNotif !== null && oldNotif !== n) oldNotif.Retainable.unlock()
    }

    // Replace приживается в самом Notification-объекте БЕЗ повторного emission
    // сигнала notification() (проверено живьём: карточка не обновилась) — live-поля
    // протаскиваем его changed-сигналами.
    function _connectLive(rec, n) {
        if (rec._liveConnected) return
        rec._liveConnected = true
        const sync = () => root._syncFromNotif(rec)
        n.summaryChanged.connect(sync)
        n.bodyChanged.connect(sync)
        n.appNameChanged.connect(sync)
        n.appIconChanged.connect(sync)
        n.imageChanged.connect(sync)
        n.urgencyChanged.connect(sync)
        n.expireTimeoutChanged.connect(sync)
        n.transientChanged.connect(sync)
        n.actionsChanged.connect(sync)
    }

    function _syncFromNotif(rec) {
        const n = rec.notif
        if (n === null) return
        rec.appName = n.appName.length > 0 ? n.appName : "notify"
        rec.icon = n.appIcon
        rec.image = n.image
        rec.iconUrl = root.iconUrlOf(n.image)
        rec.summary = n.summary
        rec.body = n.body
        rec.urgency = _urgencyOf(n)
        rec.timeout = n.expireTimeout
        rec.transient = root._transientOf(n)
        rec.time = Date.now()
        rec.dup = 1
        _syncActions(rec, n)
        if (rec.state === "toast") {
            rec.deadline = _deadlineFor(rec)
            _touchToasts()
        } else if (rec.state === "history") {
            _touchHistory()
        }
    }

    function _syncActions(rec, n) {
        const actions = []
        let hasDefault = false
        const list = n.actions || []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            if (a.identifier === "default") { hasDefault = true; continue }
            if (a.identifier === "inline-reply") continue   // ревью T4 minor 6
            actions.push({ key: a.identifier, label: a.text })
        }
        rec.actions = actions
        rec.hasDefault = hasDefault
        rec.actRefs = list
        rec.locked = actions.length > 0 || hasDefault
    }

    function _coalesce(rec, n, now) {
        rec.dup++
        rec.icon = n.appIcon
        rec.image = n.image
        rec.iconUrl = root.iconUrlOf(n.image)
        rec.summary = n.summary
        rec.body = n.body
        rec.time = now
        if (rec.state === "toast") {
            rec.paused = false
            rec.deadline = _deadlineFor(rec)
            // обновлённый — наверх стека (in-place: флаш одним присваиванием за кадр)
            const idx = root.toasts.indexOf(rec)
            if (idx > 0) { root.toasts.splice(idx, 1); root.toasts.unshift(rec) }
            _touchToasts()
        } else if (rec.state === "pending") {
            _touchPending()   // ревью T4 раунд 2 minor 3: был безусловный _touchHistory
        } else {
            _touchHistory()
        }
        _syncActions(rec, n)
        if (rec.locked && rec.notif === null) {
            // запись истории без живого объекта: объект новый — привязать и залочить
            rec.notif = n
            n.Retainable.lock()
            n.closed.connect(reason => root._onClosed(rec, reason))
        }
        n.dismiss()   // дубль-объект клиенту не нужен
    }

    function _route(rec, now) {
        // DND: critical пробивает, low/normal — сразу в историю
        if (root.dnd && rec.urgency !== 2) {
            _retireToHistory(rec)
            return
        }
        // спам >10/3s: low/normal сворачиваются в «+N»; critical проходит всегда
        // и в спам-окно не попадает (ревью T4 minor 10)
        if (rec.urgency !== 2 && _registerSpam(now)) {
            root.floodCount++
            root.lastFloodAt = now
            _retireToHistory(rec)
            return
        }
        _pushToast(rec)
    }

    function _registerSpam(now) {
        const log = root._spamLog.filter(t => now - t < root.spamWindowMs)
        log.push(now)
        root._spamLog = log
        return log.length > root.spamLimit
    }

    // ------------------------------------------------------------- тосты
    function _pushToast(rec) {
        if (root.toasts.length >= root.maxToasts) {
            let victim = -1
            for (let i = root.toasts.length - 1; i >= 0; i--) {
                if (root.toasts[i].urgency !== 2) { victim = i; break }
            }
            if (victim === -1) {
                // стек из одних critical: сверхстековый critical — в счётчик «+N critical»
                rec.state = "pending"
                root.pendingCriticals.unshift(rec)
                _touchPending()
                return
            }
            const v = root.toasts[victim]
            root.toasts.splice(victim, 1)
            if (v.notif !== null) v.notif.expire()   // клиенту NotificationClosed(…, Expired)
            v.paused = false                          // minor 13
            _retireToHistory(v)                       // → история (спека: стек ≤4)
            _touchToasts()
            // НОВЫЙ вставляется до promotion: освобождённый слот — его, иначе
            // _promotePending успеет занять слот и стек переполнится до 5
        }
        rec.state = "toast"
        rec.deadline = _deadlineFor(rec)
        root.toasts.unshift(rec)
        _touchToasts()
        _promotePending()
    }

    function _deadlineFor(rec) {
        if (rec.urgency === 2) return 0                       // critical не истекает сам
        if (rec.timeout > 0) return Date.now() + rec.timeout  // клиентское значение (мс)
        if (rec.timeout === 0) return 0                       // явное «никогда»
        return Date.now() + (rec.urgency === 0 ? root.timeoutLow : root.timeoutNormal)
    }

    function _closeToast(rec) {
        if (rec.state === "toast") {
            const i = root.toasts.indexOf(rec)
            if (i !== -1) root.toasts.splice(i, 1)
            rec.paused = false                     // ревью T4 minor 13: hover-пауза не переживает тост
            _retireToHistory(rec)
            _touchToasts()
            _promotePending()
        } else if (rec.state === "") {
            // объект закрылся до route (гонка внешнего CloseNotification)
            rec.paused = false
            _retireToHistory(rec)
        }
    }

    function _promotePending() {
        // ранний return при переполнении/реентрантности: каскад onClosed при dismiss
        // мог протолкнуть сверх maxToasts (стек из 5)
        if (root._promoting || root.toasts.length >= root.maxToasts) return
        root._promoting = true
        let moved = false
        while (root.pendingCriticals.length > 0 && root.toasts.length < root.maxToasts) {
            const next = root.pendingCriticals.shift()
            moved = true
            if (next.notif === null) {
                // объект мёртв (внешний close) — просто в историю
                _retireToHistory(next)
                continue
            }
            next.state = "toast"
            next.paused = false                    // minor 13
            next.deadline = _deadlineFor(next)
            root.toasts.push(next)
        }
        if (moved) _touchPending()
        root._promoting = false
    }

    function _onClosed(rec, reason) {
        if (rec.state === "toast" || rec.state === "") _closeToast(rec)
        else if (rec.state === "history") {
            // invoke из истории или внешний close по записи истории —
            // действия потреблены, объект больше не нужен; тач — чтобы кнопки
            // мёртвой записи ушли из UI (ревью T4 minor 8)
            _release(rec)
            _touchHistory()
        } else if (rec.state === "pending") {
            const i = root.pendingCriticals.indexOf(rec)
            if (i !== -1) root.pendingCriticals.splice(i, 1)
            _touchPending()
            _retireToHistory(rec)
        }
        if (!rec.locked) rec.notif = null   // объект умрёт сразу после обработчика
    }

    function _release(rec) {
        if (rec.locked && rec.notif !== null) rec.notif.Retainable.unlock()
        rec.locked = false
        rec.notif = null
        rec.actRefs = []
    }

    // → история. Transient в историю не пишется вовсе: записи нет ни в тостах, ни в
    // списке истории — живой объект отпускаем сразу, иначе Retainable.lock висит вечно
    // (ревью T4, Important 3б). Гвард от повторного входа: Notification.expire() →
    // closed эмитится СИНХРОННО — к моменту возврата expire() запись уже может быть
    // отретирена каскадом _onClosed (ревью T4, раунд 2 Important 1 — без гварда дубль
    // uid в ScriptModel и стек из 5).
    function _retireToHistory(rec) {
        if (rec.state === "history") return
        rec.state = "history"
        rec.time = Date.now()   // свежесть для dup/replace считается от входа в историю
        if (rec.transient) { _release(rec); return }
        _pushHistory(rec)
    }

    function _actionObj(rec, key) {
        if (rec.notif === null) return null
        const list = rec.actRefs || []
        for (let i = 0; i < list.length; i++)
            if (list[i].identifier === key) return list[i]
        return null
    }

    // Replace ищем только среди живых записей текущего процесса: стек, pending и
    // свежайшая (< freshMs) запись истории — иначе replace со «спящим» id оживит
    // закрытую запись недельной давности, а дедуп молча съест повторное уведомление
    // (ревью T4, Important 1)
    function _findById(id) {
        for (let i = 0; i < root.toasts.length; i++)
            if (root.toasts[i].bootId === root.bootId && root.toasts[i].id === id)
                return root.toasts[i]
        for (let i = 0; i < root.pendingCriticals.length; i++)
            if (root.pendingCriticals[i].bootId === root.bootId && root.pendingCriticals[i].id === id)
                return root.pendingCriticals[i]
        const now = Date.now()
        for (let i = 0; i < root.historyList.length; i++) {
            const r = root.historyList[i]
            if (r.bootId === root.bootId && r.id === id && now - r.time <= root.freshMs)
                return r
        }
        return null
    }

    // дубли — та же область, что и replace: живой стек/pending + свежая история
    function _findDup(app, summary, body) {
        const key = _keyOf(app, summary, body)
        for (let i = 0; i < root.toasts.length; i++)
            if (root.toasts[i].bootId === root.bootId && _keyOf(root.toasts[i]) === key)
                return root.toasts[i]
        for (let i = 0; i < root.pendingCriticals.length; i++)
            if (root.pendingCriticals[i].bootId === root.bootId
                && _keyOf(root.pendingCriticals[i]) === key)
                return root.pendingCriticals[i]
        const now = Date.now()
        for (let i = 0; i < root.historyList.length; i++) {
            const r = root.historyList[i]
            if (r.bootId === root.bootId && _keyOf(r) === key && now - r.time <= root.freshMs)
                return r
        }
        return null
    }

    function _keyOf(app, summary, body) {
        if (summary === undefined) return app.appName + "\u0001" + app.summary + "\u0001" + app.body
        return app + "\u0001" + summary + "\u0001" + body
    }

    // ------------------------------------------------------------- история
    function _pushHistory(rec) {
        root.historyList.unshift(rec)
        while (root.historyList.length > root.historyLimit) {
            _release(root.historyList[root.historyList.length - 1])
            root.historyList.pop()
        }
        _touchHistory()
        persistDebounce.restart()
    }

    function _touchToasts() { root._dToasts = true; root._queueFlush() }
    function _touchPending() { root._dPending = true; root._queueFlush() }
    function _touchHistory() { root._dHistory = true; root._queueFlush() }

    // ------------------------------------------------------------- сканер таймеров
    // Один таймер вместо per-record Timer (куча dynamic Timers в QML не нужна).
    Timer {
        id: scan
        interval: 250
        running: true
        repeat: true
        onTriggered: root._scan()
    }

    function _scan() {
        const now = Date.now()
        if (root.floodCount > 0 && now - root.lastFloodAt > root.spamWindowMs) {
            root.floodCount = 0   // шторм кончился
        }
        const list = root.toasts.slice()   // копия: _closeToast мутирует in-place
        for (let i = 0; i < list.length; i++) {
            const r = list[i]
            if (r.paused || r.deadline === 0) continue
            if (now >= r.deadline) {
                if (r.notif !== null) r.notif.expire()
                else _closeToast(r)
            }
        }
    }

    // «now»/«12m» в UI должны стареть: периодический тач (раз в 60с достаточно),
    // только когда тосты или центр видимы (ревью T4 minor 9)
    Timer {
        interval: 60000
        running: root.showing || LayoutState.slots.C === "notifcenter"
        onTriggered: {
            if (root.toasts.length > 0) root._touchToasts()
            if (root.historyList.length > 0) root._touchHistory()
        }
    }

    // ------------------------------------------------------------- JSONL-персист
    readonly property string persistPath:
        Quickshell.env("HOME") + "/.cache/arch-ui/notifications.jsonl"

    // Демон без надежного PATH — абсолютный путь (SPEC §7)
    Component.onCompleted: {
        root.bootId = Date.now()
        Quickshell.execDetached(["/usr/bin/mkdir", "-p",
                                 Quickshell.env("HOME") + "/.cache/arch-ui"])
    }

    FileView {
        id: storeFile
        path: root.persistPath
        printErrors: false            // первого старта файл ещё нет — не шумим
        onLoaded: root._loadDisk()
        onLoadFailed: (error) => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[archui] notif store load failed: " + error)
        }
    }

    Timer {
        id: persistDebounce
        interval: 800
        onTriggered: root._writeDisk()
    }

    function _loadDisk() {
        const text = storeFile.text()
        if (text.length === 0) return
        const now = Date.now()
        const recs = []
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.length === 0) continue
            let o = null
            try { o = JSON.parse(line) } catch (e) { continue }
            // валидация чисел: битая (руками правленая/усечённая) строка не роняет
            // загрузку и не даёт NaN-времени в UI (ревью T4 minor 11)
            if (typeof o.time !== "number" || isNaN(o.time) || o.time <= 0) continue
            if (typeof o.id !== "number" || isNaN(o.id)) continue
            if (now - o.time > root.historyTtlMs) continue   // TTL 7д
            const u = o.urgency === 0 || o.urgency === 1 || o.urgency === 2 ? o.urgency : 1   // minor 4
            recs.push({
                uid: ++root._uidSeq,
                bootId: 0,               // чужой процесс: в replace/дедупе не участвует
                id: o.id,
                appName: o.appName,
                iconUrl: "",
                icon: o.icon,
                image: "",
                summary: o.summary,
                body: o.body,
                urgency: u,
                transient: false,
                time: o.time,
                timeout: -1,
                actions: [],             // у записей из JSONL кнопок действий нет
                hasDefault: false,
                actRefs: [],
                dup: typeof o.dup === "number" && !isNaN(o.dup) && o.dup > 0 ? o.dup : 1,
                state: "history",
                notif: null,
                locked: false,
                paused: false,
                deadline: 0,
                remain: 0,
                shown: true
            })
        }
        // файл пишется в порядке historyList (новые первыми) — тот же порядок и читаем
        root.historyList = recs.slice(0, root.historyLimit)
        console.info(`[archui] notif history restored: ${root.historyList.length} entries`)
    }

    function _writeDisk() {
        const now = Date.now()
        // TTL-чистка перед записью; выкидываемые записи освобождаем — иначе
        // Retainable.lock утекает (ревью T4, Important 3а)
        const alive = []
        const dropped = []
        for (let i = 0; i < root.historyList.length; i++) {
            const r = root.historyList[i]
            if (r.transient || now - r.time > root.historyTtlMs) dropped.push(r)
            else alive.push(r)
        }
        if (dropped.length > 0) {
            for (let i = 0; i < dropped.length; i++) _release(dropped[i])
            root.historyList.length = 0
            for (let i = 0; i < alive.length; i++) root.historyList.push(alive[i])
            _touchHistory()
        }
        const lines = []
        const list = root.historyList.slice(0, root.historyLimit)
        for (let i = 0; i < list.length; i++) {
            const r = list[i]
            lines.push(JSON.stringify({
                id: r.id, appName: r.appName, icon: r.icon, summary: r.summary,
                body: r.body, urgency: r.urgency, time: Math.round(r.time), dup: r.dup
            }))
        }
        storeFile.setText(lines.length > 0 ? lines.join("\n") + "\n" : "")
    }
}
