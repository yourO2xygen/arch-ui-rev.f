# ARCH·UI v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.
> План на русском; исполнители-сабагенты читают SPEC.md + research-доки из `docs/research/`.

**Goal:** Полный desktop shell (3 колонки-слота + верхняя лента, notification daemon, pi-чат) на Quickshell 0.3.2 / Hyprland.

**Architecture:** Демон `qs -c shell` держит 6 постоянных layer-shell окон с `exclusionMode: Ignore` + `mask: Region`; панели живут в слотах колонок (Loader, замена по LayoutState); данные — сервисы-синглтоны с поллингом/push; чат — подпроцесс `pi --mode rpc` (JSONL over stdio).

**Tech Stack:** QML (Qt 6.12), Quickshell 0.3.2, Lucide path-иконки (assets/icons/icons.json), JetBrains Mono NFM + DSEG7.

**Spec:** `docs/SPEC.md` (v2) — план спорит от него; все размеры/токены/тайминги — оттуда и из `docs/research/*`.

## Global Constraints

- Логическое пространство 1600×900 (scale 1.2). Сетка: поля 24, межколонник 20, слоты x=24/548/1072, y=332, 504×544; calendar 264×288 @ x24,y24; bar ~500×44 top-center; toasts 276 wide right-24.
- Цвета ТОЛЬКО из Theme.qml: surface #000000, txt #f4f4f5, txt2 #a1a1aa, dim #56565e, ghost #3f3f46, raise .05, raise2 .09, invBg #f4f4f5/invFg #000. Никакого хроматического цвета нигде (монохром).
- Движение ТОЛЬКО из Motion.qml: apple BezierCurve(.25,.1,.25,1); panelOpen 420, contentDelay 430, contentFade 220, replaceExit 180, glitch 350/200, caretBlink 1070+900, dotPulse 2s, hover 120, killFade 400, dndToggle 160, launcherGrow 260, barTimeout 2800.
- Каждое окно: `WlrLayershell.layer: WrrLayer.Top`, `exclusionMode: ExclusionMode.Ignore`, `mask: Region` (пустая при скрытом).
- Все Process — абсолютные пути: `/home/gitgut/.pi/agent/bin/pi`, `/usr/bin/docker`, `/usr/bin/ps`, `/usr/bin/kill`, `/usr/bin/systemctl`.
- Импорты (проверены по QS-API.md): `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `Quickshell.Hyprland`, `Quickshell.Services.Notifications`, `Quickshell.Widgets`, `QtQuick`, `QtQuick.Effects`.
- Каждый коммит: `git add -A && git commit` в repo `~/.config/quickshell/shell` (identity уже настроена локально).
- Верификация каждого таска: `qs -c shell -n` в фоне → `qs log` без error/warning → IPC-проверки → `grim -g "..." /tmp/shot.png` скриншоты → Read скриншота глазами. Коммит только после чистого лога.
- Никогда не оставлять в репо пароли/ключи (auth.json pi не читать).

## Review Focus

1. **Пустой слот глотает ввод** — каждое окно с пустой маской; тест: клик/скролл над закрытой колонкой уходит в окно под ней (Task 2).
2. **Лаунчер без клавиатуры** — `keyboardFocus: Exclusive` при открытии, None при закрытии; тест: печать в открытом лаунчере идёт в поле (Task 7).
3. **Critical-уведомления исчезают** — hints-urgency byte → enum с fallback normal; тест: `notify-send -u critical` висит до ручного закрытия (Task 4).
4. **Стриминг pi рвётся** — SplitParser "\n", подписка до prompt, `agent_settled`; тест: длинный ответ приходит построчно без обрезки (Task 8).
5. **Reload обнуляет UI** — DND/слоты в PersistentProperties; тест: `ipc call archui dnd true` → правка файла → reload → DND ещё on (Task 4).

---

### Task 1: Ядро дизайн-системы — Theme, Motion, qmldir, Icon

**Files:**
- Create: `Theme.qml`, `Motion.qml`, `qmldir`, `kit/qmldir`, `kit/Icon.qml`, `kit/Section.qml`

**Interfaces:**
- Produces: синглтоны `Theme` (свойства: `surface, txt, txt2, dim, ghost, raise, raise2, invBg, invFg: color; font, fontDseg: string; strokeE: real; s6,s8,s10,s11,s12,s13,s18: int; glass: bool`) и `Motion` (`apple: EasingCurve-параметры; panelOpen, contentDelay, contentFade, replaceExit, glitchPanel, glitchLite, hoverMs, killFade, dndToggle, launcherGrow, barTimeout, caretBlink, caretPause: int`) — используются всеми后续 тасками через `import "."`/`qmldir`.
- Produces: `Icon { name: "cpu"; size: 14 }` — Shape/ShapePath рендер из `assets/icons/icons.json`, effective stroke `Theme.strokeE*24/size` (min 1.25 vb).

- [ ] **Step 1:** Написать `Theme.qml`/`Motion.qml` (pragma Singleton), значения — дословно из Global Constraints/SPEC §3. `icons.json` грузится в Icon.qml через `FileView` один раз.
- [ ] **Step 2:** `qmldir` (root): `singleton Theme 1.0 Theme.qml`, `singleton Motion 1.0 Motion.qml`; `kit/qmldir` — примитивы.
- [ ] **Step 3:** `Icon.qml` — парсер `[tag, attrs]` → ShapePath (path "M..."), stroke из правила, `asynchronous` не нужен (15KB json кэшируется).
- [ ] **Step 4:** Проверка: `qs -c shell -p <test.qml>`-объект с `Icon{name:"cpu";size:14}` на фоне — рендер без ошибок в `qs log`. (Тестовый стенд-файл потом удалить.)
- [ ] **Step 5:** Commit `feat: design system core (Theme/Motion/Icon)`.

### Task 2: Каркас окон, слоты, IPC, хоткеи

**Files:**
- Create: `shell.qml`, `services/LayoutState.qml`, `kit/Panel.qml`, `components/Placeholder.qml`
- Modify: `qmldir`, `kit/qmldir`

**Interfaces:**
- Consumes: Theme, Motion, Icon.
- Produces: `LayoutState` (Singleton): `slots: {A,B,C → panelId|"bar"|null}`, `function toggle(panelId)`, `function openIn(slot,panelId)` — логика замены из SPEC §2 (180ms выход, новая на +120ms выше по z, ghost на replace выключен), персист `PersistentProperties { reloadableId: "layout" }`.
- Produces: `Panel { head; body: Component; foot }` — окно-каркас: хореография 420/430/220 (Behavior opacity/scale на apple), ghost-эхо (2 контурных Rect), contentOpacity-таймер, пустая/прямоугольная `mask: Region`, sync со слотом.
- Produces: `shell.qml`: окна A/B/C (x=24/548/1072 y=332, 504×544), окно calendar (264×288 @24,24), окно бара, окно тостов — все с `exclusionMode: Ignore` + пустой `mask`; `IpcHandler` `archui`: `toggle(panelId: string)`, `toggleBar()`, `dismissToasts()`, `dnd(on: bool)`; `GlobalShortcut` appid `archui` name `launcher`.
- Produces: `components/Placeholder.qml` — панель-заглушка «PANEL NAME» для проверки хореографии.

- [ ] **Step 1:** LayoutState + панельная логика toggle/replace (unit-проверяемо через `qs -c shell ipc call archui toggle placeholder-a` последовательности: открыть → открыть другой → заменить → закрыть; смотреть лог + скриншоты).
- [ ] **Step 2:** Окна колонок + Panel.qml (хореография + маска). Проверка маски: окно терминала под пустым слотом получает клики (запустить `sleep 5` в foreground-окне и кликнуть по области закрытого слота — ввод не перехвачен).
- [ ] **Step 3:** Окна calendar/бара/тостов (пустые заглушки, маски).
- [ ] **Step 4:** IPC + GlobalShortcut; hyprland-бинды **временно** через `hyprctl dispatch exec` (не трогая hyprland.lua до Task 10): `hyprctl dispatch exec "qs -c shell ipc call archui toggle placeholder-a"`.
- [ ] **Step 5:** `qs log` чист, скриншоты хореографии (3 кадра grim с интервалом). Commit `feat: window skeleton, slots, IPC`.

### Task 3: Верхняя лента — StatusBar, Calendar

**Files:**
- Create: `components/StatusBar.qml`, `components/Calendar.qml`
- Modify: `shell.qml` (подключение), `services/LayoutState.qml` (bar в LayoutState)

**Interfaces:**
- Consumes: Panel-хореография, Icon, Theme, Motion.
- Produces: StatusBar — часы DSEG7 «21:47» (SystemClock, 1s), дата «sun · nov 1» (txt2 9px), воркспейсы 1–6 из `Hyprland.workspaces`+`focusedMonitor.activeWorkspace` (активный — инверсия, занятый — raise), раскладка (RawEvent "activelayout"); таймер 2800ms (hover — hold, повторный toggleBar — рестарт); клик воркспейса → `Hyprland.dispatch("workspace N")`.
- Produces: Calendar — реальный месяц, пн-старт, 42 ячейки 32px, сегодня-инверсия, ‹›навигация, ISO-неделя в foot; idle-dim 30s + сворачивание до чипа 264×40 (клик).

- [ ] **Step 1:** StatusBar + проверки данных (`hyprctl activeworkspace` сверить с баром).
- [ ] **Step 2:** Calendar; сверить с `cal` и ISO-номером недели (`date +%V`).
- [ ] **Step 3:** Скриншоты, commit `feat: status bar + calendar`.

### Task 4: Уведомления — NotifStore, Toasts, NotifCenter

**Files:**
- Create: `services/NotifStore.qml`, `components/Toasts.qml`, `components/NotifCenter.qml`
- Modify: `shell.qml`, `qmldir`

**Interfaces:**
- Consumes: Panel, Icon, Theme/Motion, LayoutState (слот C).
- Produces: `NotifStore` (Singleton): NotificationServer (caps: actions, body, body-markup, icon-static, persistence — НЕ body-images/inline-reply/sound), `history` (ScriptModel записей {id, appName, summary, body, urgency, time, actions[], icon, transient}), `dnd: bool` (PersistentProperties), `coalesce()`, JSONL-персист `~/.cache/arch-ui/notifications.jsonl` (TTL 7д, ≤200, transient не пишем), lock только при actions; critical: не истекает, пробивает DND, стек>4 → счётчик «+N critical»; дубли (app,summary,body) → «×N»; спам >10/3s → «+N».
- Produces: Toasts — стек ≤4 (276 wide, top-right), вариант-lite глича при появлении (Task 9 подключит полный), hover-пауза таймера, крестик, close по ActionInvoked/default-клик.
- Produces: NotifCenter — слот C: TODAY/YESTERDAY, строки h52, DND-тумблер (160ms) + Clear в head, у записей из JSONL кнопок действий нет, «dnd on» в foot.

- [ ] **Step 1:** NotifStore + сервер; тест-матрица из research/NOTIFICATIONS.md (чеклист в конце файла): `notify-send -u critical "t"`, `-t 0`, `-h string:x-canonical...` нет, replace_id (`notify-send -r`), actions (`-A "ok=OK"`), transient (`-e`), спам 20 подряд, дубли. Каждый случай — проверить тост/историю/лог.
- [ ] **Step 2:** Toasts + hover-пауза + коалиция.
- [ ] **Step 3:** NotifCenter + DND-персист + Clear.
- [ ] **Step 4:** Reload-тест: DND on → `touch shell.qml` (reload) → DND ещё on.
- [ ] **Step 5:** Commit `feat: full notification daemon`.

### Task 5: SysMon+SysInfo, ProcMon+TaskMgr

**Files:**
- Create: `services/SysMon.qml`, `services/ProcMon.qml`, `components/SysInfo.qml`, `components/TaskMgr.qml`

**Interfaces:**
- Consumes: Panel, Icon (cpu/memory-stick/gpu/wifi/bluetooth/usb/battery-*), SegBar, Dot, Row.
- Produces: `SysMon` (Singleton): cpu% (Δ/proc/stat), mem (proc/meminfo), gpu — **один долгоживущий** `/usr/bin/nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits -l 5` (Process+SplitParser; при отсутствии nvidia — попытка `radeontop`-нет → строки ghost); battery/network/uptime из /sys и /proc; свойства для биндинга.
- Produces: `ProcMon`: `/usr/bin/ps -eo pid,comm:40,pcpu,rss,user --sort=-pcpu --no-headers` раз в 2s **только при видимой панели**; `kill(pid)` + fade-out 400ms строки; ScriptModel.
- Produces: SysInfo (слот B): метрики 2×2 (228×92), спарклайн cpu (гистограмма, fade-in столбца 200ms), HARDWARE 2×3, чип uptime, foot user@host·ядро (`/proc/sys/kernel/osrelease`, `Quickshell.env("USER")`).
- Produces: TaskMgr (слот A): фильтр+чип сортировки, таблица h30 (~13 строк), hot-cpu жирный (≥20%), kill-кнопка hover-инверсия.

- [ ] **Step 1:** SysMon — живые значения сверить с `top`/`free`/`nvidia-smi`.
- [ ] **Step 2:** SysInfo-панель; скриншот.
- [ ] **Step 3:** ProcMon + kill-тест (spawn `sleep 300`, kill из UI, процесс исчез из `ps`).
- [ ] **Step 4:** TaskMgr-панель; Commit `feat: sysinfo + taskmgr`.

### Task 6: DockerMon + Docker

**Files:**
- Create: `services/DockerMon.qml`, `components/Docker.qml`

**Interfaces:**
- Consumes: Panel, Icon (container/play/square/refresh-cw/terminal), Row, Chip, SegBar.
- Produces: `DockerMon` (Singleton): push — `/usr/bin/docker events --format '{{json .}}' --since 0` (SplitParser; события start/die/destroy/health_status → refresh), refresh — `docker ps -a --format '{{json .}}'`; `logs(container)` — `docker logs --tail 200 -f` (живой хвост, старый Process убивается при смене контейнера); `stats(container)` — `docker stats --no-stream` по требованию; `action(start|stop|restart, container)` — `/usr/bin/docker <verb>`; свойства: containers list, version.
- Produces: Docker (слот A): список 184px слева (dot/имя/образ/порт), справа табы Logs/Resources/Ports, тулбар h26 с 4 иконками, error-строки лога — инверсия, foot `N running · M exited · версия`.

- [ ] **Step 1:** DockerMon + события (docker запущен в системе — проверить `docker ps`; если нет прав без sudo — зафиксировать в docs и рендерить ghost-состояние).
- [ ] **Step 2:** Панель + табы; логи живого контейнера (запустить `docker run -d --name t1 busybox sh -c 'while true; do echo tick; sleep 2; done'` → логи тикают → `docker rm -f t1`).
- [ ] **Step 3:** Скриншоты всех 3 табов, commit `feat: docker manager`.

### Task 7: Launcher (GlobalShortcut, 2 стадии) + Logout

**Files:**
- Create: `components/Launcher.qml`, `components/Logout.qml`
- Modify: `shell.qml` (GlobalShortcut → LayoutState.toggle("launcher")), `kit/Field.qml`, `kit/Row.qml` если ещё не созданы в Task 2-4 (создать здесь: Field, Row, Chip, Btn, SegBar, Dot — полный kit)

**Interfaces:**
- Consumes: LayoutState (слот B — launcher/logout/sysinfo), DesktopEntries, execDetached, HyprlandFocusGrab.
- Produces: Launcher — стадия 1: dock 504×48 (placeholder «run…», каретка `_` 9×2 blink 1070+900); стадия 2 (первый символ или ↑↓): список 504×372 растёт вверх 260ms, строки h34 (инициал-плитка 24, имя 11.5, категория 9 dim), фильтр подстрокой, ↑↓ + Enter-запуск `Quickshell.execDetached(DesktopEntries.byId(id).exec)` + вспышка строки + закрытие; keyboardFocus Exclusive при открытии → None при закрытии; HyprlandFocusGrab — клик мимо закрывает.
- Produces: Logout — 5 плиток h56 (lock/sleep/exit/reboot/power, power hover-инверсия): `/usr/bin/loginctl lock-session`, `/usr/bin/systemctl suspend`, `/usr/bin/hyprctl dispatch exit` (сразу, без фейда), reboot/poweroff (короткий fade-оверлей).

- [ ] **Step 1:** Полный kit (Field caret-механика: Timer 1070ms blink + 900ms пауза при вводе через `onTextEdited`).
- [ ] **Step 2:** Launcher стадия 1→2, фильтр, запуск (`Exec=firefox`-запись реально стартует).
- [ ] **Step 3:** Фокус-тесты: печать идёт в поле; клик мимо — закрылось и фокус вернулся в терминал.
- [ ] **Step 4:** Logout + команды (suspend/reboot НЕ нажимать по-настоящему — проверить только hover/рендер; exit не нажимать).
- [ ] **Step 5:** Commit `feat: launcher + logout`.

### Task 8: AgentBridge + AgentChat + AgentMgr

**Files:**
- Create: `services/AgentBridge.qml`, `components/AgentChat.qml`, `components/AgentMgr.qml`

**Interfaces:**
- Consumes: Panel, Field h40, Chip, Icon (bot/send/plus/trash).
- Produces: `AgentBridge` (Singleton): ленивый старт при первом openIn(C, *); Process `/home/gitgut/.pi/agent/bin/pi --mode rpc` (плюс минимальный профиль без MCP — проверить флаги 1.4.0 по `pi --help`, фактическую команду записать в docs/agent-chat.md); stdout SplitParser("\n"); JSON-парсинг событий: `message_update.text_delta` → append, `agent_settled` → конец, `agent_start`; очередь записи в stdin (`running` check); `send(text)`, `steer(text)`, `setModel(id)`, `newThread()`, `stats()` → contextUsage; extension-диалоги (confirm/select) → сигнал `question(parts)`; `connected/died` состояние.
- Produces: AgentChat (слот C): лента (user-инверсия/bot-raise2), стриминг дельт, команды `▸ cmd`, typing-точки 1.2s, agent-question карточка с кнопками, поле h40 + стрелка.
- Produces: AgentMgr (слот C): табы Active/History, RUNNING (точки), MODELS (радио из rpc списка моделей, default/local теги), кнопки New/Kill, чип contextUsage.

- [ ] **Step 1:** AgentBridge: запустить pi rpc вручную, снять фактические имена событий из `~/.pi/agent/install/releases/1.4.0/.../docs/rpc.md`, реализовать; лог всех входящих событий в консоль для отладки.
- [ ] **Step 2:** AgentChat: отправить «say hello step by step» — дельты стримятся, settled закрывает индикатор; steer во время генерации.
- [ ] **Step 3:** AgentMgr: список моделей, смена, New thread (старый процесс → newSession rpc или restart), contextUsage.
- [ ] **Step 4:** Отказ: `kill` процесса pi → статус-строка + перезапуск по кнопке.
- [ ] **Step 5:** Commit `feat: pi agent chat + manager`.

### Task 9: GlitchFX + полировка движения

**Files:**
- Create: `kit/GlitchFX.qml`
- Modify: `kit/Panel.qml` (подключить на открытие), `components/Toasts.qml`, `components/StatusBar.qml`

**Interfaces:**
- Consumes: Motion.glitchPanel(350)/glitchLite(200).
- Produces: `GlitchFX` — ShaderEffect: vertex passthrough, fragment — построчный x-сдвиг `hash(floor(uv.y*N), floor(t*24.))`, моно-двоение (2 alpha-выборки со смещением ±2px, усилить яркость краёв), инверсия полос `step(0.97, hash(row,t))`, flicker `mix(1., 0.7+0.3*step(.5,hash(t)), envelope)`, скан-линия вниз, envelope `1-t` за 350ms; `live` только пока идёт.
- Produces: lite-вариант для тостов/бара: SequentialAnimation flicker + x-jitter ±2px + 2 инверсные полосы, 200ms.

- [ ] **Step 1:** GlitchFX на Panel; запись экрана (`wf-recorder`/`grim`-серия) — визуальная проверка монохромности (пипеткой по кадрам: только grayscale).
- [ ] **Step 2:** GPU-цена: `hyprctl rollinglog`/`QS_LOG=render` или замер FPS (MangoHud недоступен — замер через `perf top` кратко; критерий: нет джанка на открытие).
- [ ] **Step 3:** Lite на тосты/бар. Commit `feat: glitch reveal`.

### Task 10: hyprland.lua, docs, финиш

**Files:**
- Modify: `~/.config/hypr/hyprland.lua` (заменить старые qs-строки: автостарт `qs -c shell --no-duplicate --daemonize`, бинды из SPEC §12; бекап строки уже в tar-архиве)
- Create: `docs/README.md`, `docs/design-system.md`, `docs/motion.md`, `docs/layout.md`, `docs/notifications.md`, `docs/agent-chat.md`, `docs/services.md`

- [ ] **Step 1:** Доки по правилу SPEC §11 (главный README ссылается на остальные; как что работает без чтения кода).
- [ ] **Step 2:** hyprland.lua: заменить 4 строки (exec_cmd автостарт, menu, SUPER+A sysinfo-бинд, window-rules namespaces — обновить под новые `namespace` окон: `archui:*`).
- [ ] **Step 3:** Полный e2e: перезапуск демона, все хоткеи, все панели, уведомления, чат. `qs log` чист.
- [ ] **Step 4:** Commit `docs: full documentation + hyprland integration`. Открытые вопросы SPEC §13 — вывести пользователю в финальном отчёте.

### Task 11 (условный, только после одобрения пользователя): Стекло

**Files:** Create `kit/Glass.qml`; Modify `kit/Panel.qml`, `Theme.qml` (флаг `glass` уже определён).

- [ ] **Step 1:** ShaderEffectSource контента (live:false, обновление ≤10fps), flip Y в шейдере, MultiEffect blur 3px, opacity .14, градиентная маска до 24% высоты, блик .05 дрейф 9s, halo radial.
- [ ] **Step 2:** Замер цены кадра; критерий смерти SPEC §9 (>2ms/джанк → фича удаляется, Theme.glass=false не создаёт текстуры).
- [ ] **Step 3:** Commit `feat: glass effect (optional)`.
