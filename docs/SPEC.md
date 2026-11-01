# ARCH·UI v2 — архитектурная спека рабочего стола на Quickshell

> Статус: **v2** (после критики, п.12) → в реализацию. Quickshell 0.3.2, Qt 6.12, Hyprland 0.57, логическое пространство **1600×900** (физ. 1920×1080, scale 1.2).
> Источники: [research/DESIGN.md](research/DESIGN.md) — дизайн-идея; [research/ANALYSIS.md](research/ANALYSIS.md) — разбор макета (токены, SVG, анимации, фактические отступы); [research/QS-API.md](research/QS-API.md) — API Quickshell; [research/NOTIFICATIONS.md](research/NOTIFICATIONS.md) — протокол уведомлений; [research/PI-BACKEND.md](research/PI-BACKEND.md) — бекенд чата; [research/DESIGN-RESEARCH.md](research/DESIGN-RESEARCH.md) — сетка, иконки, карта состояний.

---

## 0. Требования пользователя (дано)

1. 3 колонки (лево/центр/право), симметрия. Вверху только: calendar (лево) / status bar (центр) / тосты уведомлений (право). Внизу: taskmgr+docker — лево; launcher+logout+sysinfo — центр; agent chat+agent manager+notif center — право.
2. Панели колонки занимают **одинаковый** слот 504×544; вызов второй **заменяет** первую на месте.
3. Daemon-режим (`qs -c shell -n -d`).
4. Монохромный киберпанк-глич при появлении.
5. Стекло-эффект — опция, после ядра, с критерием смерти (§9).
6. Бекенд чата — pi `--mode rpc`.
7. Полный notification daemon.
8. Токены/кривые — в одном месте (Theme.qml / Motion.qml).
9. Сабагенты; каждое техрешение → критика → правка.
10. Docs: главный README → вторичные.

---

## 1. Структура проекта

```
~/.config/quickshell/shell/
├── shell.qml              # ShellRoot: окна колонок/ленты, IPC, GlobalShortcut, синглтоны
├── Theme.qml              # ТОКЕНЫ: цвета, шрифты, размеры (Singleton)
├── Motion.qml             # ДВИЖЕНИЕ: длительности, кривые, параметры глича (Singleton)
├── kit/                   # ОБЩИЕ ЭЛЕМЕНТЫ (примитив добавляется вторым использованием)
│   ├── Panel.qml          # head/body/foot + хореография (420/430/220) + ghost-эхо + глич + mask
│   ├── Icon.qml           # Lucide path → Shape/ShapePath (retained), stroke-правило
│   ├── Row.qml            # строка: hover raise, selected inset, dot-слот
│   ├── SegBar.qml  Dot.qml  Chip.qml  Btn.qml  Field.qml  Section.qml
│   └── GlitchFX.qml       # ShaderEffect монохромного глича
├── components/            # StatusBar Calendar Toasts Launcher Logout SysInfo TaskMgr Docker AgentChat AgentMgr NotifCenter
├── services/              # LayoutState NotifStore AgentBridge SysMon ProcMon DockerMon (Singleton)
├── assets/{fonts,icons}/  # DSEG7Classic-Bold.ttf, icons.json (84 lucide-набора, 15KB)
└── docs/
```

Зависимости: `components → kit → Theme/Motion`; `components → services`; services не импортируют UI. Синглтоны через `pragma Singleton` + `qmldir`.

**Состояние и reload**: синглтоны пересоздаются при авторелоаде qs — состояние, которое должно переживать reload, держится ТОЛЬКО в `PersistentProperties` (с `reloadableId`) внутри синглтона либо на диске (FileView/JsonAdapter). Обязательный минимум: DND (NotifStore), открытые слоты (LayoutState), история уведомлений (файл), поколение чата.

---

## 2. Layout: слоты, окна, маски ввода

```
┌──────────────────────────────────────────────────────────┐  y=24
│ calendar 264×288      bar ~500×44          toasts 276×N  │  верхняя лента
├──────────┬──────────────┬──────────────┬─────────────────┤  низ, y=332
│  СЛОТ A  │    СЛОТ B    │    СЛОТ C    │   (пусто)       │  высота 544
│  504×544 │    504×544   │    504×544   │                 │
└──────────┴──────────────┴──────────────┴─────────────────┘
  x=24        x=548          x=1072
```

**Окна** (создаются один раз, живут всегда — демон):
- 3 окна колонок (PanelWindow, layer top) — **отдельные окна**, не одно широкое: независимые маски и фокус проще, 3 доп. поверхности приемлемы по памяти (решение зафиксировано до каркаса).
- Окно calendar, окно бара, окно тостов.

**Критично — ввод и exclusion** (нашлось в критике): каждое окно получает
`exclusionMode: Ignore` (не отъедает место у тайлов) и `mask: Region`:
- слот закрыт / бар скрыт / тостов нет → **пустая маска** (окно прозрачно для ввода);
- панель открыта → прямоугольник панели; маска переключается в той же хореографии, что и visible. Никогда не полагаемся на ввод по геометрии.

**KeyboardFocus** (WlrLayershell): launcher — `Exclusive` при открытии, чат — `OnDemand`, всё остальное — `None`. При закрытии — назад в `None`. Клик мимо панели → закрытие по `HyprlandFocusGrab` (для лаунчера) / потеря OnDemand-фокуса (чат остаётся открытым).

**Slot manager** (`LayoutState`, Singleton): `{A,B,C} → panelId|null`, персист в PersistentProperties. `toggle(panelId)`:
- слот показывает `panelId` → закрыть (зеркальная хореография);
- слот пуст → открыть (полная: панель 420ms → контент на 430-й мс 220ms + ghost-эхо + глич);
- слот показывает другую → **замена**: старая уходит 180ms (fade + scale .97, **без ghost-эхо** — две волны эха читаются как грязь), новая стартует на +120ms **выше по z** (Loader-стек, клип по слоту), фокус переходит явно.

**Жизнь панелей**: после первого открытия экземпляр панели живёт всегда (`Loader.active` не выключаем — деактивация уничтожила бы состояние; невидимое и так не рендерится в SceneGraph). «Спим» только тяжёлое: `enabled/visible` списков, пульс точек, анимации — биндим на `panelVisible`.

**Launcher dock**: dock 504×48 — **первый кадр открытия лаунчера** (стадия 1), в закрытом слоте B не существует ничего. Список (стадия 2) растёт вверх от нижней кромки слота, 260ms.

Верхняя лента: calendar — персистентен **по требованию пользователя**, но с режимами: idle >30s без взаимодействия с ним → dim (opacity .55), клик по дате-чипу → сворачивание до чипа 264×40 и обратно. Bar — транзиент 2.8s (по DESIGN.md), вопрос Q4b о минимальных постоянных часах.

---

## 3. Дизайн-система (Theme.qml / Motion.qml)

`Theme.qml` — единственное место цветов/размеров: surface #000000, txt #f4f4f5, txt2 #a1a1aa, dim #56565e, ghost #3f3f46, raise rgba(255,255,255,.05), raise2 .09, invBg/invFg для инверсии, strokeE 1.5 (effective stroke иконок: `stroke_vb = 36/size`, пол 1.25). Отступы — фактические значения макета (6/8/10/11/12/13/18 — шкала «кратно 4» в CSS макета не соблюдалась, переносим факт). Шрифты: `"JetBrainsMono NFM"` (400–700, системный) + DSEG7 (FontLoader из assets). Флаг `Theme.glass` — гейтит не видимость, а **создание** текстур стекла.

`Motion.qml` — единственное место движения: `apple = BezierCurve(.25,.1,.25,1)`; panelOpen 420 / contentDelay 430 / contentFade 220; ghostEcho +40/+140 (scale .99→.952, .45→0), **на replace отключено**; replaceExit 180; glitch 350 (панели) / 200 (тосты/бар); caretBlink 1070 (+пауза 900); dotPulse 2s InOutSine только у filled; hover 120; killFade 400; dndToggle 160; launcherGrow 260; barTimeout 2800; toastHover — пауза таймера.

**Глич** (монохром, п.7): `GlitchFX.qml` — ShaderEffect над `layer.enabled` контента панели. Построчный x-сдвиг срезов `hash(uv.y, floor(t*24fps))`, моно-двоение двумя alpha-копиями (не RGB), инверсия случайных полос, flicker яркости, скан-линия. 350ms → `ShaderEffectSource.live=false`, постоянная GPU-цена ноль. Тосты/бар — дешёвый вариант: flicker + x-джиттер ±2px + 2 инверсные полосы. Джиттерим Item внутри поверхности, не окно.

---

## 4. Компоненты: слот 504×544, интерьеры

Анатомия: head 40 / body pad 12·16·16 / foot 30 → **body ≈ 474px**. Макетные интерьеры (ANALYSIS) пересчитаны под слот:

| Панель | Body-раскладка под 504×544 | Скролл |
|---|---|---|
| SysInfo | метрики 2×2, ячейка 228×92 (значение 15 + юнит, подпись, полоса, спарклайн у cpu); HARDWARE 2×3 строки h28 | нет |
| TaskMgr | фильтр 34 + чип сортировки; таблица: строки h30 (pid/name/cpu/mem/user/kill), видно ~13 | таблица |
| Docker | слева список 184px (dot/имя/образ/порт), справа табы Logs/Resources/Ports + тулбар h26 | обе части |
| AgentChat | лента пузырей, поле h40; карточки команд `▸ cmd` и agent-question | лента |
| AgentMgr | табы; RUNNING строки h30; MODELS радио h28; кнопки New/Kill h26 | секции |
| NotifCenter | TODAY/YESTERDAY строки h52 (плитка 32 + тексты), DND/Clear в head | история |
| Logout | 5 плиток h56 × 96w (ряд), user·uptime секция, крупная мета | нет |
| Launcher | dock h48 → список 504×372: строки h34 (инициал 24/имя/категория) | список |

Каждый компонентный сабагент получает этот скелет + ANALYSIS.md и уточняет внутренние отступы по фактическим значениям макета.

Данные: StatusBar — SystemClock + `Hyprland.workspaces`/`focusedMonitor` + раскладка (RawEvent); Calendar — JS Date, **ISO-8601 неделя** (макет считал не по ISO — исправлено); Launcher — `DesktopEntries` + `execDetached`; Logout — systemctl/hyprctl; SysInfo — SysMon; TaskMgr — ProcMon; Docker — DockerMon; чат/менеджер — AgentBridge; тосты/центр — NotifStore.

Logout-команды: lock → `loginctl lock-session`, sleep → `systemctl suspend`, exit → `hyprctl dispatch exit` (**сразу, без фейда — композитор умрёт**), reboot/poweroff → команда сразу + короткий fade-оверлей (экран всё равно уйдёт; оверлей только на случай медленного выключения).

---

## 5. Уведомления

Сервер — `Quickshell.Services.Notifications`. Подробности граблей — research/NOTIFICATIONS.md.

- **Capabilities**: actions, body, body-markup, icon-static, persistence. **НЕ заявляем**: body-images (raw image-data недоступен из QML, строгий rowstride-парсер QS не обойти — ложная capability дала бы «полосатые» аватарки), inline-reply (Q6 дефолт — нет), sound, append, action-icons.
- **Urgency**: hints byte → enum вручную с fallback **normal** (не low!). `expireTimeout` — миллисекунды. Critical ⇒ не истекает сам, таймаут клиента игнорируется.
- **Тосты** (верх-право, стек до 4, критические включительно): normal/low — по таймауту (hover — пауза), critical — только вручную. Critical сверх стека → счётчик «+N critical» (клик → NotifCenter), чтобы 3 залипших critical не закрывали стек навсегда.
- **Коалиция**: дубли по (app, summary, body) — счётчик «×N» на карточке (сетевой флап раз в 5с не должен штормить). Спам >10/3s — свёртка «+N». `transient` — **никогда не персистим**, в историю не пишем (volume-OSD).
- **История** (NotifCenter): все не-transient уведомления; данные **копируются в свой стор** (JSONL `~/.cache/arch-ui/notifications.jsonl`, TTL 7 дней, лимит 200). `Retainable.lock()` — только для уведомлений **с действиями**, unlock при удалении записи (TTL/лимит/Clear). У записей, загруженных из JSONL после рестарта, кнопки действий скрыты (объектов-то нет). TODAY/YESTERDAY по локальной дате.
- **replace_id** — обновление карточки в тосте и истории, без дублей. **CloseNotification** извне — тост закрывается, история остаётся. **keepOnReload** — переигрывание после reload; дублей по (id, generation) нет.
- **Модель «тосты верх-право / центр низ-право» — окончательная** (Q1). При DND: low/normal — сразу в историю, critical — пробивает тостом.

---

## 6. Чат/менеджер агента — pi RPC

`AgentBridge` ↔ подпроцесс **`pi --mode rpc`** (JSONL over stdio). Детали — research/PI-BACKEND.md.

- **Ленивый старт**: процесс запускается при первом открытии колонки C (cold start 1–2с один раз), дальше живёт. Не гоняем 150–300MB Node-процесса неделями для неиспользуемой панели.
- **Облегчённый профиль чата**: без MCP и лишних расширений (если флаги не сработают — `--no-mcp`/точечный `-e`, проверить на 1.4.0; запасной вариант — полный профиль, зафиксировать фактическую команду в docs/agent-chat.md).
- stdout — **SplitParser по "\n"**; события подписаны до первого prompt; корреляция по id; ждём `agent_settled`. stdin — очередь записи (write до running теряется).
- Автокомпакция: `set_auto_compaction` включить; `get_session_stats.contextUsage` → чип в AgentMgr.
- Сессия: Q3 дефолт — in-memory + кнопка New thread.
- Extension-диалоги (confirm/select от pi-subagents) → карточка «agent question» в чате.
- Падение процесса → статус-строка + кнопка перезапуска.

---

## 7. Daemon, хоткеи, IPC

- Запуск: `qs -c shell --no-duplicate --daemonize` из hyprland.lua (как раньше). Systemd-юнит не возвращаем — один источник старта.
- **Лаунчер — GlobalShortcut** (`Quickshell.Hyprland`, appid `archui`, name `launcher`; bind `bind = SUPER, R, global, archui:launcher`) — нулевая латентность, без форка qs. Остальное — IPC (`IpcHandler` `archui`): `toggle(panelId)`, `toggleBar()`, `dismissToasts()`, `dnd(bool)`; в hyprland — `bind = ..., exec, qs -c shell ipc call archui toggle docker`. Типы аргументов обязательны.
- **Абсолютные пути** для всех Process: pi → `/home/gitgut/.pi/agent/bin/pi`, docker → `/usr/bin/docker`, ps/kill/systemctl — `/usr/bin/...` (PATH демона ненадёжен).
- Авторелоад включён (состояние переживается по §1).

---

## 8. Производительность

- Поллинг: clock 1s; SysMon — cpu/mem из /proc 2s (дёшево), **GPU — один долгоживущий `nvidia-smi --query-gpu=... --format=csv -l 5`** (Process+SplitParser, не форк на тик); SysMon активен всегда (дешёвые /proc-чтения), GPU-поток — только когда SysInfo виден либо всегда (замерить; nvidia-smi -l почти бесплатен после старта).
- **DockerMon**: один `docker events --format json` (push) + refresh `docker ps` по событию и при открытии панели; `docker logs -f` на выбранный контейнер вместо повторных `--tail`.
- ProcMon 2s — только когда TaskMgr виден.
- Невидимые панели: биндинги/анимации спят (§2), Loader не деактивируется.
- Icon.qml — **Shape/ShapePath** (retained-дерево, без перерастеризации), не Canvas; fallback — layer-кэш.
- GlitchFX live 350ms; стекло — §9.

---

## 9. Стекло (опция, фаза 2, критерий смерти)

Перевёрнутая копия контента панели (ShaderEffectSource, flip Y), MultiEffect blur 3px, opacity .14, градиентная маска до 24% высоты, блик .05 (дрейф 9s), halo radial. **Критерий смерти**: если кадр с стеклом на этой машине (iGPU) стоит >2ms или джанчит — фича выкидывается целиком, не тюнится. `Theme.glass=false` не создаёт текстуры вообще.

---

## 10. Этапы

1. **Каркас**: Theme/Motion/qmldir/kit (Icon, Panel с масками/фокусом), LayoutState, 3 окна колонок + окно calendar/бара/тостов с масками, IPC+GlobalShortcut, хоткеи, демон. Критерий: панели-пустышки открываются/заменяются/закрываются, ввод не глотается на пустых слотах.
2. **Лента+уведомления**: StatusBar, Calendar, Toasts, NotifStore+NotifCenter (полный daemon).
3. **Системные панели**: SysInfo, TaskMgr, Docker, Launcher, Logout.
4. **Агент**: AgentBridge, AgentChat, AgentMgr.
5. **Глич-полировка** по карте состояний.
6. **Стекло** (опц.), финальные docs, hyprland.lua.

Этап = сабагент-реализатор → проверка живьём (`qs`+, скриншоты через grim/hyprctl) → сабагент-критик (п.12) → правки → docs.

---

## 11. Документация

`docs/README.md` (главный) → `design-system.md`, `motion.md`, `layout.md` (окна/маски/IPC/хоткеи), `notifications.md`, `agent-chat.md`, `services.md`, `research/*`. Правило: изменение поведения → сначала doc.

---

## 12. Хоткеи (заменяют старые в hyprland.lua)

| Клавиши | Действие |
|---|---|
| SUPER+R | launcher (GlobalShortcut) |
| SUPER+S / D / T | sysinfo / docker / taskmgr |
| SUPER+C / L | calendar / logout |
| SUPER+A / SUPER+SHIFT+A | agent chat / agent mgr |
| SUPER+N / SUPER+SHIFT+N | notif center / DND toggle |
| SUPER+SHIFT+S | status bar |

## 13. Открытые вопросы пользователю (дефолты выбраны, работа не блокируется)

1. «Уведомления» дважды (верх-право и низ-право) → тосты вверху, центр внизу. Верно?
2. Wallpaper: оригинал из спеки отсутствует; что ставить? (не трогаю)
3. Чат: одна сессия in-memory + New thread? (да)
4. Права инструментов pi: confirm-диалоги в UI? (нет, только статус)
5. Модель чата по умолчанию? (дефолт pi)
6. Звуки/inline-reply уведомлений? (нет)
7. Фоновые сабагенты pi в AgentMgr? (нет, v1)
8. Critical строго не истекает? (да)
9. Бар: оставить транзиент (по макету) или добавить постоянные мини-часы? (транзиент, по макету)
10. Calendar: ок ли idle-dim + сворачивание до чипа? (сделано мягко)
11. Хоткеи §12 — конфликты с вашими?
