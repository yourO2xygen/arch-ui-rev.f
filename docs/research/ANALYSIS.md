# ANALYSIS · index.html → Quickshell (QML)

Технический разбор макета `index.html` (v9 · system, 1155 строк) для переноса в Quickshell.
Сверка со спецификацией `DESIGN.md` выполнена; расхождения помечены ⚠.

---

## 1. CSS-токены (`:root`, строки 48–61)

```css
--surface:#000;                 /* фон панелей */
--raise:rgba(255,255,255,.05);  /* ховер */
--raise2:rgba(255,255,255,.09); /* выбрано / нажато */
--txt:#f4f4f5;                  /* основной текст */
--txt2:#a1a1aa;                 /* вторичный текст */
--dim:#56565e;                  /* метки, мета */
--ghost:#3f3f46;                /* отключённое / плейсхолдер / дни вне месяца */
--mono:'JetBrains Mono',ui-monospace,monospace;
--seg7:'DSEG7-Classic','JetBrains Mono',monospace;  /* только часы в баре */
--apple:cubic-bezier(.25,.1,.25,1);                 /* кривая всех движений */
--s1:4px; --s2:8px; --s3:12px; --s4:16px; --s5:20px; --s6:24px;  /* spacing scale */
```

Прочие «токеноподобные» константы, встречающиеся в CSS литералами (для QS — вынести в тему):

| Значение | Где используется |
|---|---|
| `rgba(255,255,255,.5)` | бордер ghost-контуров (`1px solid`) |
| `rgba(255,255,255,.09)` | `.sep` в баре (1×16 вертикальный разделитель) |
| `rgba(255,255,255,.06)` | правый разделитель списка docker (`border-right:1px`) |
| `rgba(255,255,255,.03)` | фон `.log`, `.qcard`, `.prow` |
| `rgba(255,255,255,.04)` | фон плиток logout (`.pw`) |
| `rgba(255,255,255,.25)` | столбики спарклайна (`.spark i`), `.hi` → `--txt` |
| `rgba(255,255,255,.14)` | скроллбар (4px, thumb) |
| `#000` на `--txt` фоне | инверсия (solid-кнопки, чипы, today, hot-kill, user-bubble, ошибки в логе, активные табы/воркспейсы) |

### Типографика (реальные размеры из CSS, не только из DESIGN.md)

| Стиль | font | Применение |
|---|---|---|
| `.p-head .t` | 600 11px/1, ls .12em, uppercase, txt2 | заголовок панели |
| `.p-foot` | 400 9px/1, ls .06em, dim | подвал |
| `.lbl` | 500 9px/1, ls .14em, uppercase, dim | метка секции |
| `.row` | 400 11px/1.2, txt2 | строка |
| `.row .rt` | 500 11px/1, txt | имя в строке |
| `.row .rb` | 400 9.5px/1.2, txt2 | подпись |
| `.row .meta` | 9px, dim | правая мета |
| `.btn` | 500 10.5px/1 | кнопка, h 26 |
| `.chip` | 500 10px/1, pad 4×8 | чип |
| `.kbd` | 500 10px/1, pad 4×7 | клавиша |
| `.mv` | 600 15px/1, txt + `span` 9px/500 dim | значение + юнит |
| `.ms` | 400 9px/1, dim | подпись метрики |
| поле `.field input` | 400 12.5px/1 | инпут |
| `.ldock input` | 400 14px/1 | инпут лаунчера |
| `#clock .t` | **700 15px `--seg7`**, ls .02em | часы DSEG7 |
| `#clock .d` | 500 10.5px, dim, ls .06em | дата |
| `.ws-i` | 600 10.5px, 22×22 grid | воркспейс |
| `#bar .bl` | 500 11px, #fff | раскладка EN |
| `.app .nm` | 500 11.5px / `.aicon` 600 10.5px / `.ct` 9.5px dim | строка лаунчера |
| `.cal-c` | 500 11px, h 34 | ячейка календаря |
| `.cal-dow span` | 500 8.5px, h 20 | дни недели |
| `.cal-nav .m` | 600 12px | «November 2026» |
| `.crow .cn` 10.5 / `.ci` 9 / `.cp` 8.5 | docker-список | |
| `.log` | 400 10px/**1.7**, txt2 | терминальный блок |
| `.tbl th` 9 caps / `.tbl td` 11, h 30 | таблица процессов | |
| `.msg` | 400 11px/**1.5**, max-width 88% | пузырь чата |
| `.ntf .nt` 600 11.5 / `.nb` 10/1.4 / `.ntime` 9 | тосты | |
| `.nrow .nt` 10.5 / `.rb` 9.5 | строки notifmgr | |

Шрифты подключаются: JetBrains Mono 400/500/600/700 (Google Fonts), DSEG7-Classic (`dseg@0.46.0` jsdelivr). Для QS — ttf локально + `FontLoader`.

### ⚠ Расхождения токенов с DESIGN.md

1. **Масштаб отступов нарушается в самом CSS.** Токены `--s5`(20)/`--s6`(24) объявлены, но **ни разу не используются** (используются только s2/s3/s4). При этом «некратные» значения сплошь и рядом: `.metric{padding:10px 12px}`, `.log{padding:10px}`, `.qcard{padding:10px 11px}`, `.msg{padding:8px 11px}`, `.ntf{padding:12px 13px; gap:11px}`, `.tool{padding:5px 9px}`, `.kbd{padding:4px 7px}`, `.dbg-b{padding:6px 9px}`, `#bar{gap:13px; padding:0 18px}`, `.pw-grid{gap:6px}`, `.apps{gap:2px}`, `.tbl{border-spacing:0 2px}`, `.cal-*{gap:2px}` и т.д. Для QS: кратность 4 — лишь ориентир, переносить нужно фактические значения.
2. **Каретка**: DESIGN.md «8×2» — верно для `.field` (8×2, margin-top 3px), но в лаунчере `.ldock .fcaret` — **9×2**, `margin-top:4px`. В QML-компоненте каретки сделать ширину параметром.
3. **Поле лаунчера не `.field`**: `.ldock` h 48, **фон прозрачный** (нет `raise2`), паддинг 24px (плейсхолдер на left 26). DESIGN.md описывает поле как «фон raise2» — к лаунчеру это не относится.
4. **DSEG7 вес**: DESIGN.md «bold» — в CSS `font:700 15px` (совпадает; размер 15px в DESIGN не указан).
5. Остальные токены (`surface/txt/txt2/dim/ghost/raise/raise2/apple`) — **полное совпадение** с DESIGN.md.

---

## 2. Inline SVG-иконки (спрайт `<defs>`, строки 429–469)

Общие параметры рендера (`.svg.ic`, строка 129):
```css
svg.ic{fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round}
.ic{width:15px;height:15px}   /* базовый размер; в шапке панели .p-head .ic = 14×14 */
```
Все viewBox = `0 0 24 24`. В QML — тот же path с `stroke-width:1.8`, масштаб через width/height.

Ниже **все 35 символов дословно**. [НЕ ИСП.] — объявлен, но в разметке не используется.

| id | Использование | Path data / примитивы |
|---|---|---|
| `i-search` | [НЕ ИСП.] | `<circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/>` |
| `i-wifi` | sysinfo·network, notifmgr·Bluetooth(вчера), тост Bluetooth | `<path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M8.5 16a6 6 0 0 1 7 0"/><circle cx="12" cy="19.5" r="1" fill="currentColor" stroke="none"/>` |
| `i-bt` | sysinfo·bluetooth, notifmgr(вчера), тост 1 | `<path d="m7 7 10 10-5 5V2l5 5L7 17"/>` |
| `i-bat` | sysinfo·battery | `<rect x="2" y="8" width="16" height="9" rx="2.5"/><line x1="21.5" y1="11" x2="21.5" y2="14"/>` |
| `i-bolt` | notifmgr·Power | `<path d="M13 2 4 14h6l-1 8 10-13h-7z"/>` |
| `i-cpu` | [НЕ ИСП.] | `<rect x="5" y="5" width="14" height="14" rx="2.5"/><rect x="10" y="10" width="4" height="4"/><line x1="9" y1="2" x2="9" y2="5"/><line x1="15" y1="2" x2="15" y2="5"/><line x1="9" y1="19" x2="9" y2="22"/><line x1="15" y1="19" x2="15" y2="22"/><line x1="2" y1="9" x2="5" y2="9"/><line x1="2" y1="15" x2="5" y2="15"/><line x1="19" y1="9" x2="22" y2="9"/><line x1="19" y1="15" x2="22" y2="15"/>` |
| `i-gpu` | [НЕ ИСП.] | `<rect x="2" y="6" width="19" height="12" rx="2.5"/><circle cx="9" cy="12" r="3"/><line x1="15" y1="10" x2="17.5" y2="10"/><line x1="15" y1="14" x2="17.5" y2="14"/><line x1="4" y1="18" x2="4" y2="21"/><line x1="8" y1="18" x2="8" y2="21"/>` |
| `i-vram` | [НЕ ИСП.] | `<rect x="4" y="4" width="16" height="16" rx="2.5"/><rect x="9" y="9" width="6" height="6"/>` |
| `i-clock` | [НЕ ИСП.] | `<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>` |
| `i-power` | logout·power | `<path d="M18.4 6.6a9 9 0 1 1-12.8 0"/><line x1="12" y1="2" x2="12" y2="10"/>` |
| `i-lock` | logout·lock | `<rect x="4" y="11" width="16" height="10" rx="2.5"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>` |
| `i-moon` | logout·sleep | `<path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/>` |
| `i-logout` | logout head + logout·exit | `<path d="M9 21H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3"/><path d="m16 17 5-5-5-5"/><line x1="21" y1="12" x2="9" y2="12"/>` |
| `i-reboot` | logout·reboot, docker-тулбар (restart) | `<path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.9-3.4L23 10"/><path d="M20.5 15a9 9 0 0 1-14.9 3.4L1 14"/>` |
| `i-x` | крестик тостов (12×12) | `<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>` |
| `i-chl` | calendar ‹ (13×13) | `<path d="m15 18-6-6 6-6"/>` |
| `i-chr` | calendar › (13×13) | `<path d="m9 18 6-6-6-6"/>` |
| `i-send` | chat кнопка отправки (13×13) | `<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/>` |
| `i-play` | docker start (12×12) | `<path d="M6 4l14 8-14 8z"/>` |
| `i-stop` | docker stop (12×12), aimgr Kill (12×12) | `<rect x="6" y="6" width="12" height="12" rx="2"/>` |
| `i-term` | docker attach (12×12) | `<path d="m4 17 6-6-6-6"/><line x1="12" y1="19" x2="20" y2="19"/>` |
| `i-box` | notifmgr·Docker, тост 2 | `<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7 12 12l8.7-5"/><line x1="12" y1="22" x2="12" y2="12"/>` |
| `i-shield` | sysinfo·vpn | `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>` |
| `i-bell` | notifmgr head | `<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>` |
| `i-msg` | notifmgr·KDE Connect / Discord | `<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>` |
| `i-plus` | chat «+» (13×13), aimgr New (12×12) | `<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>` |
| `i-down` | notifmgr·Firefox (download) | `<line x1="12" y1="4" x2="12" y2="20"/><path d="m6 14 6 6 6-6"/>` |
| `i-hd` | sysinfo·usb, notifmgr·Pacman | `<line x1="22" y1="12" x2="2" y2="12"/><path d="M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/>` |
| `i-container` | docker head (lucide) | `<path d="M22 7.7c0-.6-.4-1.2-.8-1.5l-6.3-3.9a1.72 1.72 0 0 0-1.7 0l-10.3 6c-.5.2-.9.8-.9 1.4v6.6c0 .5.4 1.2.8 1.5l6.3 3.9a1.72 1.72 0 0 0 1.7 0l10.3-6c.5-.3.9-1 .9-1.5Z"/><path d="M10 21.9V14L2.1 9.1"/><path d="m10 14 11.9-6.9"/><path d="M14 19.8v-8.1"/><path d="M18 17.5V9.4"/>` |
| `i-bot` | aimgr head (lucide) | `<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/>` |
| `i-gauge` | sysinfo head (lucide) | `<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>` |
| `i-activity` | taskmgr head (lucide) | `<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>` |
| `i-sparkles` | chat head (lucide) | `<path d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"/><path d="M20 2v4"/><path d="M22 4h-4"/><circle cx="4" cy="20" r="2"/>` |
| `i-memstick` | [НЕ ИСП.] (lucide) | `<path d="M12 12v-2"/><path d="M12 18v-2"/><path d="M16 12v-2"/><path d="M16 18v-2"/><path d="M2 11h1.5"/><path d="M20 18v-2"/><path d="M20.5 11H22"/><path d="M4 18v-2"/><path d="M8 12v-2"/><path d="M8 18v-2"/><rect x="2" y="6" width="20" height="10" rx="2"/>` |
| `i-cal` | calendar head (lucide) | `<path d="M8 2v3"/><path d="M16 2v3"/><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18"/>` |

Особые случаи:
- `i-wifi`: точка — **залитая**, `fill="currentColor" stroke="none"`.
- Иконки в «плитках» (`.aicon`, `.nico`) — 12×12 внутри плитки 24/32; в тулбаре docker и кнопках — 12–13px.
- [НЕ ИСП.] всего 6: `i-search, i-cpu, i-gpu, i-vram, i-clock, i-memstick` — метрики sysinfo обходятся **без** иконок (только текстовые метки).

---

## 3. Анимации (полный список)

### 3.1 Открытие/закрытие панели (главный ритм)
```css
.cmp{transition:opacity .42s var(--apple),transform .42s var(--apple)}
.cmp.hidden{opacity:0;transform:scale(.97);pointer-events:none}
.cmp > *{opacity:1;transition:opacity .22s ease}
.cmp.pre > *{opacity:0}
.cmp.pre.hidden > *{transition:none}   /* при старте из скрытого контент не мигает */
```
- Панель: opacity 0→1 + scale .97→1, **420ms**, `cubic-bezier(.25,.1,.25,1)`.
- Контент: fade **220ms ease**, класс `pre` снимается JS-таймером **OPEN_MS = 430ms**.
- Закрытие — зеркало: `pre`+`hidden` ставятся сразу.
- JS: `showC` ставит `zIndex=++zTop` (счётчик от 100) и `setTimeout(remove 'pre', 430)`; для лаунчера фокус в инпут через 430+50ms.

### 3.2 ghost-эхо (только на открытие)
```css
@keyframes ghost{0%{opacity:.45;transform:scale(.99)}100%{opacity:0;transform:scale(.952)}}
/* база: inset:0; border:1px solid rgba(255,255,255,.5); pointer-events:none */
.panel:not(.hidden)::before, #bar:not(.hidden)::before {animation:ghost .62s var(--apple) .04s both}
.panel:not(.hidden)::after,  #bar:not(.hidden)::after  {animation:ghost .62s var(--apple) .14s both}
.llist:not(.hidden)::before {animation:ghost .5s  var(--apple) .03s both}
.llist:not(.hidden)::after  {animation:ghost .5s  var(--apple) .11s both}
#notifs:not(.hidden) .ntf::before {animation:ghost .55s var(--apple) .05s both}
#notifs:not(.hidden) .ntf::after  {animation:ghost .55s var(--apple) .13s both}
```
| Хост | Длительность | Задержки (2 контура) |
|---|---|---|
| `.panel`, `#bar` | 620ms | 40ms / 140ms |
| `.llist` (список лаунчера) | 500ms | 30ms / 110ms |
| `.ntf` (каждый тост) | 550ms | 50ms / 130ms |

⚠ DESIGN.md приводит только вариант панелей (`.99→.952`, `.45→0`, +40/+140) — для llist/ntf параметры иные (см. выше).

### 3.3 Пульс / мигание / вспышки
| Имя | Свойства | Применение |
|---|---|---|
| `pulse` | `0%,100%{opacity:1}50%{opacity:.4}`, **2s infinite** | `.dot-run` |
| `blink` | `0%{opacity:1}50%{opacity:0}100%{opacity:0}`, **1.07s steps(1,end) infinite** | каретка `.field.focus .fcaret`, `.ldock.focus .fcaret`; `.typing` → `animation:none; opacity:1`, снимается через 900ms после ввода |
| `flash` | `0%{background:rgba(255,255,255,.3)}→transparent`, **.45s ease** | строка лаунчера при Enter/клике |
| `tp` | `0%,100%{opacity:.25}50%{opacity:1}`, **1.2s infinite**, delays 0/.15s/.3s | 3 точки «набирает» в чате (5×5px, gap 3, dim) |
| `sheen` | `0%,100%{translateX(-6%)}50%{translateX(6%)}`, **9s ease-in-out infinite** | блик стекла |

### 3.4 Ховер/стейт-переходы (transition)
| Элемент | transition |
|---|---|
| `.btn` | background .15s, color .15s, transform .1s; `:active{scale(.96)}` |
| `.dbg-b` | то же; `:active{scale(.97)}` |
| `.ws-i` (бар) | all .2s |
| `.llist` (стадия 2) | opacity .32s / transform .32s, `--apple`, `scale(.97)`, **transform-origin:50% 100%** |
| `.app`, `.crow` | background .12s |
| `.cal-c` | background .15s |
| `.dtab`, `.tab`, `.kill`, `.pw`, `.nx` | all .15s (`.nx` .12s); `.pw:active{scale(.95)}` |
| `.sw` (DND) | background .2s; бегунок `::after` — all .2s |
| `#powerfx` | opacity .5s ease (держится 1500ms) |
| `#debug` | transform .5s / opacity .3s, `--apple`; `.tucked{translate(-100%,-50%)}` |
| `#dbg-tab` | opacity .3s, background/color .15s |
| kill-строка (JS) | `opacity .4s` → `remove()` через 420ms |
| закрытие тоста (JS) | `all .3s`, opacity→0 + `scale(.95)` → `remove()` через 300ms |

### 3.5 Тайминги логики (JS)
| Событие | Значение |
|---|---|
| контент после панели | **430ms** (`OPEN_MS`) |
| автоскрытие бара | **2800ms**, рестарт по повторному вызову, пауза при `:hover` |
| ответ в чате | **1100ms** (сначала индикатор набора) |
| пауза каретки при вводе | **900ms** |
| powerfx | **1500ms** |
| `show all` каскад | шаг **80ms**, порядок `bar, sysinfo, calendar, notifmgr, logout, docker, taskmgr, chat, aimgr, launcher, notifs` |
| `#debug` старт | 120ms |
| часы | `setInterval 1000ms` |

---

## 4. Эффект «стекло» (детально, строки 406–418 + JS 1139–1152)

Структура: в каждый хост вставляется `<div class="glass">` с ребёнком `<div class="r">`, в который клонируется **всё содержимое хоста**.

```css
.glass{position:absolute;inset:0;z-index:6;pointer-events:none;overflow:hidden}
/* слой 1 — отражение */
.glass .r{position:absolute;inset:0;transform:scaleY(-1);
  filter:blur(3px);opacity:.14;mix-blend-mode:screen;
  mask:linear-gradient(to bottom,rgba(0,0,0,.9),transparent 24%)}
/* слой 2 — спекулярный блик (::before) */
.glass::before{content:'';position:absolute;inset:-40%;
  background:linear-gradient(115deg,transparent 42%,rgba(255,255,255,.05) 50%,transparent 58%);
  animation:sheen 9s ease-in-out infinite}   /* translateX(-6%) ↔ 6% */
/* слой 3 — рассеянный halo (::after) */
.glass::after{content:'';position:absolute;inset:0;
  background:radial-gradient(120% 60% at 50% -10%,rgba(255,255,255,.04),transparent 60%)}
body.no-glass .glass{display:none}   /* тумблер — клавиша f */
```

Хосты (JS): все `.panel`, `#bar`, `#llist`, все `.ntf`, `#f-launch` — итого **14** экземпляров стекла.

Реализация клона:
```js
const c = host.cloneNode(true);
c.classList.remove('hidden','pre','cmp','tucked','focus');
c.style.cssText='position:absolute;left:0;top:0;width:100%;height:100%;'+
  'right:auto;bottom:auto;margin:0;opacity:1;transform:none;pointer-events:none';
```

Ключевые факты для QS:
- Отражение — **перевёрнутая по Y копия содержимого**, прижатая к геометрии панели (`inset:0` + `scaleY(-1)`); видно только верхние **24%** из-за маски (маска живёт в системе координат `.r`, где верх = низ панели после flip), стартовая альфа маски **.9**.
- **`mix-blend-mode:screen`** — чёрный фон панели в отражении исчезает, отражается только светлый контент. В QS: `ShaderEffectSource` панели + `ShaderEffect` (flip-Y, блюр, градиентная альфа); blend screen реализовать в шейдере (`src + dst − src*dst`).
- ⚠ **Клон статический**: снимается один раз при загрузке и не обновляется (часы/календарь в отражении заморожены; классы `hidden/pre` сняты — в отражении всегда «полный контент»). DESIGN.md это помечает: в QS — живой `ShaderEffectSource`.
- Стекло не перехватывает ввод (`pointer-events:none`), z-index 6 — над контентом панели.
- Блик: полоса под **115°**, прозрачная → `rgba(255,255,255,.05)` в центре (50%) → прозрачная (42%–58%), слой раздут `inset:-40%`, дрейф ±6% за 9s.
- Halo: радиальный `120% 60% at 50% -10%`, `rgba(255,255,255,.04)` → transparent 60%.
- Отключение — класс `no-glass` на `<body>` (клавиша `f`).

---

## 5. Структура и контент компонентов

Анатомия панели: `.p-head` 40px (icon 14 + title 11 caps, gap 10, pad 0 16; `.right{margin-left:auto; gap:8}`) → `.p-body` (flex-column, **gap 16**, padding **12 16 16**) → `.p-foot` 30px (9px dim, space-between). Панели: `position:absolute; background:#000; overflow:hidden`.

### 5.1 bar — статус-бар (transient)
- CSS: `#bar{left:660px→JS 960−w/2; top:0; height:44px; z-index:50; display:flex; gap:13px; padding:0 18px}`. Ширина авто (факт ≈500).
- Контент: воркспейсы 1–6 (`.ws-i` 22×22; `on`=инверсия+700; `occ`=raise/txt2; пустой=dim), sep 1×16 `rgba(255,255,255,.09)`, `EN` (11px #fff), sep, часы `21:47` (DSEG7 700 15px) + `sun · nov 1` (10.5px dim).
- Данные: **часы/дата — реальные** (tick 1s). Воркспейсы (on=1, occ=2,3) и раскладка EN — **захаркожены**; клик/цифры 1–6 лишь перекрашивают квадраты (в QS — `Hyprland.dispatch`).

### 5.2 launcher — 2 стадии
- `#launcher{left:685; bottom:0; 550×420; z-index:55; justify-content:flex-end}` — **не** `.panel` (без head/foot-кита); стеклом покрываются его дети.
- Стадия 1: `.ldock` h 48, прозрачный, input 14px, паддинг 0 24, плейсхолдер `run…` (left 26), каретка **9×2** (margin-top 4).
- Стадия 2: `.llist` (372px = 420−48), padding 12 16 16, открытие .32s scale .97 от низа (origin 50% 100%) + своё ghost-эхо.
- Строки `.app`: h 30, gap 10, pad 0 8, межстрочный gap 2; плитка-инициал 24×24 (raise2, 600 10.5px), имя 11.5 txt, категория 9.5 dim справа; `.sel` = raise2 + inset 2px маркер.
- Подвал: `↑↓ navigate · ⏎ run` | `9 apps` (счётчик от фильтра).
- Данные — **полный мок**: Firefox/web, Alacritty/term, VS Code/dev, OBS Studio/media, Spotify/audio, Steam/games, Thunar/files, Settings/system (инициал «⚙»), Calculator/util. Поиск — по `data-n` (строчные: «firefox web browser» и т.п.); Enter/клик — только вспышка, ничего не запускается.

### 5.3 sysinfo (520×484 @ 24,60)
- Head: `i-gauge` + `SYSTEM` + чип `up 3d 4h`.
- Body: `.mgrid` 2×2 (gap 8); `.metric` — фон raise, padding **10 12**, gap 6:
  - cpu: `23.4%`, `ryzen 7 7800x3d · 61°`, bar 23%, **спарклайн** 12 столбиков (высоты 30,45,38,60(hi),52,41,55(hi),34,48,42(hi),36,50(hi) % от 14px);
  - memory: `9.2 / 32 GB`, `612 processes`, bar 29%;
  - gpu: `12.1%`, `rtx 4070 · 48°`, bar 12%;
  - vram: `6.4 / 12 GB`, `2 gpu procs`, bar 53%.
- Секция `HARDWARE` (5 строк `.hrow` h 30, метка-колонка 84px, иконка 12px):
  battery `82% · 2h 40m` / `charging`; network `↓ 24.3 ↑ 2.1 MB/s` / `wlan0 · HomeNet`; vpn `wireguard · wg0` / `10.6.0.4 · 32 ms`; bluetooth `WH-1000XM4 · MX Master` / `2 connected`; usb `YubiKey 5 · SanDisk 64GB` / `3 devices`.
- Foot: `gitgut@arch · linux 6.12` | `idle · 61°`.
- Данные: **всё захаркожено**.

### 5.4 calendar (270×400 @ 552,60)
- Head: `i-cal` + `CALENDAR` (без чипов).
- Body: `.cal-nav` — `November 2026` (600 12px, margin-right:auto) + 2 кнопки 22×22 (`i-chl`/`i-chr` 13×13); `.cal-dow` MO…SU (8.5px, h 20, gap 2); `.cal-grid` — 42 ячейки, h 34, gap 2; `.out`→ghost, `.today`→инверсия+700.
- Foot: `week 44` | `nov 2026`.
- Данные: **месяц/сегодня/неделя — реальные** (старт недели — понедельник: `lead=(getDay()+6)%7`). ⚠ Номер недели — упрощённая формула (не ISO-8601). Кнопки ‹ › **не работают** (нет обработчиков) — всегда текущий месяц.

### 5.5 notifmgr (420×484 @ 838,60)
- Head: `i-bell` + `NOTIFICATIONS` + right: lbl `dnd` (8.5px) + тумблер `.sw` (32×18, бегунок 14×14) + кнопка `Clear` (h 26).
- Body: скролл (gap 2). `TODAY` — 5 строк `.nrow` h 34 (плитка 24×24 raise + иконка 12, title 10.5, body 9.5, meta 9):
  Firefox `archinstall.iso — download complete` 12m; Docker `watchtower updated 3 containers` 34m; KDE Connect `Pixel 8: photo received` 1h; Pacman `14 packages available` 2h; Power `charger connected — 82%` 3h.
  `YESTERDAY` — 2 строки `.old` (opacity .4): Discord `3 new messages · #linux` 1d; Bluetooth `MX Master 3S disconnected` 1d.
- Foot: `7 unread` | `dnd off`.
- Поведение: DND → `.muted` (список opacity .3) + foot `dnd on`; Clear → секция `EMPTY`, счётчик `0 unread`.
- Данные: **всё мок**.

### 5.6 logout (276×184 @ 1620,60)
- Head: `i-logout` + `SESSION`.
- Body: `.pw-grid` 5 равных колонок, gap 6; плитки h 56, фон `rgba(255,255,255,.04)`, gap 7, иконка 16 + caps-метка 8.5px:
  lock, sleep(`i-moon`), exit(`i-logout`), reboot, power(`i-power`, `.warn` → ховер = белая заливка + чёрные иконка/текст).
- Foot: `gitgut@arch` | `up 3d 4h`.
- Поведение: клик → полноэкранный `#powerfx` (чёрный, opacity .5s, текст = `data-fx`: `locked`/`suspended`/`logged out`/`rebooting`/`system halted`; 12px, ls .3em, uppercase, dim), снятие через 1500ms. z-index 200 — выше всего.
- Данные: user/uptime — мок.

### 5.7 docker (456×496 @ 24,560)
- Head: `i-container` + `DOCKER` + чип `6 containers`.
- Тулбар `.dk-top` (gap 8): `nginx-proxy` (600 12px), чип-solid `running`, распорка, 4 кнопки-иконки 26×26: play/stop/reboot/term.
- Split (gap 12): слева `.dk-list` **168px**, справа разделитель `1px rgba(255,255,255,.06)`, pad-right 10; строки `.crow` h 30 (gap 8): dot + имя 10.5 + образ 9 + порт 8.5:
  nginx-proxy/nginx:1.27/`80·443` (sel), postgres-db/postgres:17/5432, redis-cache/redis:8/6379, watchtower/containrrr/wt/`—`, vault/hashicorp/vault/8200 — все `dot-run`; arch-builder/archlinux:base/`exited` — `dot-exit`, порт выделен (txt,600).
- Табы `.dtabs` (pad 6×10, 10px, активный — инверсия) + 3 `.dpane`:
  - **Logs**: `.log` фон `rgba(255,255,255,.03)`, pad 10, 10px/**1.7**; 8 строк `HH:MM:SS источник | сообщение`; время dim; warn `.lv-w` (txt,700); error `.lv-e` — **инверсия** (`color:#000; background:var(--txt); padding:0 3px`): `21:42:02 nginx-proxy 429 rate-limit 10.0.0.9`.
  - **Resources**: 4 `.rrow` (label + значение + bar): CPU 2.4%, MEM 128 MB/1 GB (12.5%), NET I/O ↓12·↑8 kB/s (8%), BLOCK I/O 4.2·1.1 MB (5%) + `.prow` `health | /health → 200 · 30s`.
  - **Ports**: `80/tcp | 0.0.0.0:80 → 80`, `443/tcp | 0.0.0.0:443 → 443`, `8080/tcp | 127.0.0.1:8080 → 80`, lbl `networks`, `bridge | 172.18.0.2`.
- Foot: `5 running · 1 exited` | `docker 27.3`.
- Данные: **всё мок** (логи — статичный HTML). Табы/выбор контейнера переключаются, но контент справа не меняется.

### 5.8 taskmgr (456×496 @ 496,560)
- Head: `i-activity` + `TASK MANAGER` + чип `142 procs`.
- Тулбар: поле (flex:1, h 34, `filter processes…`, каретка) + чип-solid `cpu ▾` (сортировка — мок).
- Таблица `.tbl` (`border-spacing:0 2px`): `pid | name | cpu % (r) | mem (r) | user | (пусто, r)`; th 9px caps h 22 pad 4×10; td h 30 pad 0 10, 11px.
- 10 строк (user `gitgut`, кроме systemd/root): firefox 2201/38.2 hot/4.8 GB; ollama-runner 5102/22.7 hot/6.4 GB; code 3120/12.4/2.1 GB; docker-compose 4211/6.4/210 MB; Hyprland 1842/3.1/612 MB; Xwayland 908/1.8/340 MB; qutebrowser 12902/8.9/1.8 GB; kitty 6612/1.2/96 MB; pipewire 2288/0.9/48 MB; systemd 77/0.0/12 MB.
  - `.hot` (жирный белый) проставлен вручную при cpu ≥ 20 (совпадает с правилом DESIGN).
  - `kill · 15` (9px, pad 5×8) видна на hover/selected, ховер — инверсия; клик — fade 400ms → remove.
- Foot: `10 / 142 · sorted by cpu` | `del · term`.
- Данные: **всё мок**; фильтр по подстроке работает.

### 5.9 chat (456×496 @ 968,560)
- Head: `i-sparkles` + `AGENT CHAT` + right: чип-solid `sonnet-4.5`, чип `#142`, кнопка `+` 26×26.
- Лента (gap 8, scroll): `.msg.user` «summarize my docker containers» (инверсия, справа); `.tool` «▸ docker ps --format '{{.Names}}'» (10px dim на raise); `.msg.bot` «4 running, 1 exited. nginx-proxy and postgres-db are healthy, redis-cache restarted 2h ago.» (raise2, слева); `.qcard` (фон .03, pad 10×11): lbl `agent question` + `Table`(solid)/`JSON`/`Markdown`.
- Поле: h **40**, pad-right 48, плейсхолдер `ask anything…`, кнопка-solid 28×28 с `i-send` (13×13) справа (right:6).
- Отправка (Enter/клик): пузырь user → `.typing` (3 точки) → через **1100ms** ответ-мок: `Done — mocked response. In Quickshell this streams token-by-token.`
- Данные: **вся история — мок**; модель/тред — мок.

### 5.10 aimgr (456×496 @ 1440,560)
- Head: `i-bot` + `AGENTS` + чип `2 active`.
- Табы `.tabs` (фон raise, pad 3, gap 4): `Active · 2` (инверсия) | `History` — переключение **не реализовано**.
- `RUNNING` (`.srow` h 32): `refactor-hypr` / `sonnet-4.5 · 312 tok/s` / `12m`, dot-run; `nix-migrate` / `gpt-5.2 · idle` / `3m`, dot-idle.
- `MODELS` (`.mrow` h 28, радио 12px border 1.5 dim, выбранное — заливка inset 2.5px): sonnet-4.5 (sel, чип-solid `default` 8.5px), opus-4.1, gpt-5.2, qwen3:14b (чип `local`). Выбор не реализован.
- Низ: New(`i-plus`) / Kill(`i-stop`), flex:1, gap 8, margin-top:auto, pad-top 12.
- Foot: `sonnet-4.5 · 84k ctx` | `2 agents`.
- Данные: **всё мок**.

### 5.11 notifs — тосты (@ 1620,264, w 276, авто)
- Контейнер прозрачный (не панель), flex-column, gap 8, z-index 60.
- Карточка `.ntf`: pad **12 13**, gap 11, фон #000; плитка 32×32 (raise2, иконка 15px); title 600 11.5; body 10/1.4 (+margin-top 4); время 9 dim; крестик `.nx` 12×12 (dim, pad 3) — **виден всегда** (⚠ DESIGN.md: «крестик на hover»; в CSS он постоянный, ховер лишь подсвечивает).
- Тост 1: `i-bt`, `Bluetooth`, `WH-1000XM4 connected · 74%`, `now`.
- Тост 2 (`hint`): `i-box`, `Docker`, `arch-builder exited (0) ` + серый курсив `· click to open`, `2m ago`.
- Закрытие: opacity→0 + scale .95, 300ms → remove. Появление — общий профиль + ghost на каждой карточке.

### 5.12 Прочее
- `#debug` — пульт превью (212px, слева по центру, z 75), `#dbg-tab` язычок `›` 16×76 (z 76) — **в QS не переносится**.
- `#powerfx` — полноэкранная чёрная заглушка (z 200).
- `#stage` — масштабирование `translate(-50%,-50%) scale(min(w/1920,h/1080))` (в QS не нужно).

---

## 6. Раскладка / координаты

| Компонент | CSS (index.html) | DESIGN.md | Вердикт |
|---|---|---|---|
| bar | `left:660→JS 960−w/2`, `top:0`, h 44, w авто | top-center ≈500×44 | ✔ |
| launcher | `left:685; bottom:0; 550×420` | bottom-center 550×420 | ✔ |
| sysinfo | `24,60 520×484` | x24 y60 520×484 | ✔ |
| calendar | `552,60 270×400` | x552 y60 270×400 | ✔ |
| notifmgr | `838,60 420×484` | x838 y60 420×484 | ✔ |
| logout | `1620,60 276×184` | x1620 y60 276×184 | ✔ |
| docker | `24,560 456×496` | x24 y560 456×496 | ✔ |
| taskmgr | `496,560 456×496` | x496 y560 456×496 | ✔ |
| chat | `968,560 456×496` | x968 y560 456×496 | ✔ |
| aimgr | `1440,560 456×496` | x1440 y560 456×496 | ✔ |
| notifs | `1620,264 w 276, h авто` | x1620 y264 276×авто | ✔ |

Таблица DESIGN.md **полностью подтверждается**, расхождений по геометрии нет.

z-index: bar 50, launcher 55, notifs 60, панели — динамически `++zTop` от 100 (клик/mousedown), debug 75/76, powerfx 200. В QS порядок решается layer-ями, стек панелей — один слой с ручным z.

---

## 7. Детали для переноса, которых нет в DESIGN.md

1. **Реальные данные — только 3 места**: часы+дата бара; сетка календаря (текущий месяц, сегодня, 42 ячейки, старт с понедельника); счётчики строк лаунчера/тасктмгр при фильтрации. **Всё остальное — мок.**
2. **Формат даты бара** — строчные англ. сокращения `sun … sat`, `jan … dec` (не локализованы; для QS решить вопрос локали).
3. **Скроллбары**: 4px, thumb `rgba(255,255,255,.14)`, трек прозрачный.
4. **`::selection`** — инверсия; `user-select:none` везде, кроме инпутов; `caret-color:transparent` (каретка рисуется вручную).
5. **Курсор** системный `default` везде, pointer только на кликабельных.
6. **Маска сегментированной полосы** (точно): `repeating-linear-gradient(90deg,#000 0 4px,transparent 4px 7px)` — штрих 4px, промежуток 3px, период 7px. Контейнер h 4 фон raise, заливка `--txt` по значению.
7. **Точка состояния**: 7×7 radius 50%; `dot-run` = txt + pulse 2s; `dot-idle` = ghost; `dot-exit` — **`box-shadow: inset 0 0 0 1px var(--dim)`** (полая через inset-тень, не border).
8. **Inset-маркер выбранной строки**: `box-shadow: inset 2px 0 0 var(--txt)` поверх raise2.
9. **Спарклайн cpu**: 12 столбиков, ширина 3, gap 2, блок h 14, выравнивание по низу; обычные `rgba(255,255,255,.25)`, «горячие» `.hi` — txt.
10. **Лог docker**: error — инверсия с горизонтальным паддингом 3px; warn — просто txt+700.
11. **Тумблер DND**: 32×18, бегунок 14×14 offset 2; ON — фон txt, бегунок #000 left 16.
12. **Порядок каскада** `show all`: `bar, sysinfo, calendar, notifmgr, logout, docker, taskmgr, chat, aimgr, launcher, notifs` (80ms).
13. **Хоткеи макета без super**: `r d s t l n c a`, `⇧s`→bar, `⇧n`→notifmgr, `⇧a`→aimgr, `1–6` воркспейсы, `esc` скрыть всё, `h` пульт, `f` стекло. Буквы **не перехватываются при фокусе в инпуте**. `#static` → класс `no-anim` (`transition/animation:none !important` на всё); `#only=a,b` — подмножество. Для QS — dev-флаги.
14. **Bar-ховер**: mouseenter отменяет таймер, mouseleave перезапускает **полные** 2800ms (не остаток).
15. **Клик по панели** поднимает её наверх стека (`front()`), тоже у бара.
16. **`.cmp.pre.hidden > *{transition:none}`** — предотвращает вспышку контента: в QS контент-таймер надо сбрасывать при закрытии (`clearTimeout`).
17. **Стекло не у всех**: у лаунчера — на `#llist` и `#f-launch` (не на самом `#launcher`), у тостов — на каждой карточке. Итого 14 отдельных `ShaderEffectSource`.
18. **DSEG7** используется только для `#clock .t` (fallback JetBrains Mono).
19. **Обои**: `wallpaper.jpg` (`center/cover`, fixed); оригинал `~/Изображения/cyberpunk-2077-katana-phantom-liberty-nait-siti.jpg`.
20. **Мок-ответ чата** прямо отсылает к QS: `"Done — mocked response. In Quickshell this streams token-by-token."` — стриминг токенов в макете не реализован.
