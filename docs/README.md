# ARCH·UI — рабочий стол на Quickshell

Монохромный киберпанк-шелл для Hyprland: три слот-колонки панелей, транзиентный
статус-бар, календарь, полный notification daemon и агент-чат на `pi --mode rpc`.

Полная спека: [SPEC.md](SPEC.md) (поведение, решения, открытые вопросы).
Дизайн-исследования: [../research/](../research/).

## Установка (чистая машина)

1. **Файлы**: репозиторий кладётся в `~/.config/quickshell/shell` (config name — `shell`).
2. **Демон**: `qs -c shell --no-duplicate --daemonize`. Автостарт — в hyprland.lua:
   `hl.exec_cmd("qs -c shell --no-duplicate --daemonize")` внутри `hl.on("hyprland.start", …)`.
   Логи после рестарта — только qslog by-id (см. «Запуск» ниже).
3. **Конфиг hyprland** (`~/.config/hypr/hyprland.lua`): блок биндов ARCH·UI
   (helper `archui(panel)`, глобал лаунчера `hl.dsp.global("archui:launcher")`),
   blur-правила `layer_rule` для namespaces `archui:*`, маска dunst:
   `systemctl --user mask dunst.service` (шелл сам — notification daemon).
4. **Зависимости**: quickshell 0.3.2, qt6-shadertools (qsb), hyprland 0.57;
   опционально `sudo usermod -aG docker gitgut` (панель docker без ghost «no permission»).
5. **Экран**: сетка рассчитывается от фактического логического разрешения
   (базовый дизайн — 1600×900, scale 1.2; шрифты/размеры — Theme.px от scale
   монитора). Контент-шрифты +25% к терминальному эталону (Task 24); окно
   слота B динамическое — dock лаунчера ~50px, со списком ~190, logout ~241
   (низ всегда у H−pad); окно статус-бара 360·px (~375). Сверяйся с
   docs/layout.md.

## Запуск

Каноническая команда (одна единственная форма — хоткеи, автостарт и
reap-логика DockerMon рассчитаны именно на неё):

```
qs -c shell --no-duplicate --daemonize
```

- Демон **обязателен**: окна создаются один раз и живут всегда; панели
  открываются/закрываются через IPC, сам процесс не перезапускается.
- Автостарт прописан в `~/.config/hypr/hyprland.lua` (`hl.on("hyprland.start", …)`).
  Другого источника старта (systemd-юнита) нет — сознательно, один источник.
- Не запускай `qs -c shell` во втором терминале «на попробовать» —
  `--no-duplicate` защищает от двойного демона, но live-правки проверяй
  **полным рестартом** демона (hot-reload QS не всегда поднимает новый инстанс
  синглтона и не всегда применяет правки компонентов).

Логи демона: `qs log` (по instance-id: `qs log --id <id>`). Stdout демона — не
источник правды, warn/error смотри в qslog.

## Карта документации

| Документ | О чём |
|---|---|
| [layout.md](layout.md) | Слоты A/B/C, замена панелей, маски ввода, keyboardFocus, IPC |
| [design-system.md](design-system.md) | Токены Theme, примитивы kit, шейдеры глича |
| [motion.md](motion.md) | Все токены движения, кривая apple, семантика глича |
| [notifications.md](notifications.md) | Полный цикл уведомлений, DND, спам-гейт, история, маска dunst |
| [agent-chat.md](agent-chat.md) | pi RPC-мост, протокол, жизненный цикл процесса |
| [services.md](services.md) | Каждый синглтон: что читает, какие процессы держит, когда активен |

Правило (SPEC §11): изменение поведения → сначала doc.

## IPC-шпаргалка

Таргет `archui`:

```
qs -c shell ipc call archui toggle <panelId>   # panelId: docker|taskmgr|launcher|logout|sysinfo|chat|aimgr|notifcenter
qs -c shell ipc call archui toggleBar          # статус-бар (транзиент 2.8s)
qs -c shell ipc call archui osd brightness     # ОСД яркости в статус-баре (громкость ловится Pipewire сам)
qs -c shell ipc call archui toggleCalendar     # показать/скрыть календарь
qs -c shell ipc call archui dndToggle          # DND on/off
qs -c shell ipc call archui dnd <true|false>   # DND явно
qs -c shell ipc call archui dismissToasts      # убрать все тосты
```

`toggle` — настоящий тумблер: повторный вызов по открытой панели её **закрывает**
(в тестах это путает: «лишний» вызов молча гасит панель).

Лаунчер — не IPC, а GlobalShortcut (`archui:launcher`), бинд
`bind = SUPER, R, global, archui:launcher` — нулевая латентность.

## Хоткеи (SPEC §12)

| Клавиши | Действие |
|---|---|
| SUPER+R | лаунчер (GlobalShortcut) |
| SUPER+Z / SUPER+SHIFT+A / SUPER+A | sysinfo / docker / taskmgr (слот A) |
| SUPER+C / L | показать/скрыть календарь / logout (слот B) |
| SUPER+D / SUPER+SHIFT+D | чат / менеджер агента (слот C) |
| SUPER+N / SUPER+SHIFT+N | центр уведомлений / DND toggle |
| SUPER+X | статус-бар |
| SUPER+SHIFT+S | скриншот-регион |

Файл: `~/.config/hypr/hyprland.lua` (вне репо). Спец-воркспейс «magic» остаётся
закомментированным в файле; свободные клавиши после Task 12: SUPER+S, SUPER+T.

## Что не проверено автоматом (за пользователем)

Клик-синтез в сессии недоступен (wtype/ydotool/wlrctl нет, `hyprctl dispatch
movecursor` сломан lua-диспетчером — hyprwm/Hyprland#14675), поэтому руками
стоит проверить:

- клики по kill-кнопке TaskMgr, строкам/табам/кнопкам Docker, строкам лаунчера;
- клик-фокус полей (фильтр TaskMgr, поле чата), клавиатура в лаунчере/чате;
- hover-эффекты (power-плитки Logout, строки списков);
- Esc в лаунчере, клик мимо панели (закрытие лаунчера через focus-grab);
- тосты: hover-пауза таймера, клик «+N critical».

## Известный шум в `qs log`

Пре-existing, не ошибки шелла: предупреждение регистрации в host-portal
(`App info not found for 'archui'`), `textinput`/`disableSurface` от Qt wayland
при открытии/закрытии текстовых полей, WARN SysMon о не существующем nvidia-smi (на этой машине
его нет — SysMon специально показывает ghost «—» и не дёргает процесс повторно).

## Открытые вопросы (SPEC §13)

См. конец [SPEC.md](SPEC.md). Ключевой живой: дефолтный провайдер чата —
`settings.json` pi говорит eliza/glm-5-3, но endpoint eliza недоступен
(подробности в [agent-chat.md](agent-chat.md)).
