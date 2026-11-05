# archui · Quickshell shell для Hyprland

Минималистичный монохромный шелл для Hyprland на [Quickshell](https://quickshell.outfoxxed.me):
три слота-панели, транзиентный статус-бар, календарь, тосты. Чистый ч/б без акцентов —
единственный «акцент» это инверсия. JetBrainsMono NFM, hairline-рамки, silk-подписи.

Дизайн-система и макеты: [docs/design-brief-2026-11-05.md](docs/design-brief-2026-11-05.md) ·
[docs/design-proposal-2026-11-05.html](docs/design-proposal-2026-11-05.html) (живой макет) ·
[docs/research/DESIGN-RESEARCH-2026-11-05.md](docs/research/DESIGN-RESEARCH-2026-11-05.md)

## Состав интерфейса

| Панель | Слот | Бинд |
|---|---|---|
| SysInfo — CPU/MEM/GPU, шкалы-сегменты, hw-датчики | A (лево) | `SUPER+Z` |
| Launcher — терминальная строка поиска `›` | B (центр) | `SUPER+R` |
| Logout — плитки LOCK/SLEEP/EXIT/REBOOT/POWER | B (центр) | `SUPER+L` |
| Notifications — история + DND `[OFF\|ON]` | C (право) | `SUPER+N` |
| Calendar — date-first, ISO-недели, без часов | отдельное окно (лево-верх) | `SUPER+C` |
| Status bar V4 — ячейки ws/lng/clk + шкала суток | нижняя кромка, центр | `SUPER+X` |

Тосты — право-верх, автоскрытие, глитч на появлении. ОСД (громкость/яркость) — второе
состояние статус-бара, кроссфейд 130ms.

## Запуск

Автозапуск для Hyprland сидит в `~/.config/hypr/hyprland.lua` (`qs -c shell --no-duplicate --daemonize`).
Вручную: `qs -c shell --no-duplicate --daemonize`, лог — `qs -c shell log`, IPC —
`qs -c shell ipc call archui <toggle|toggleBar|toggleCalendar|osd|...>`.

## Архитектура

- `shell.qml` — точка входа: слоты A/B/C, окно календаря/бара/тостов, IpcHandler.
- `components/` — панели (SysInfo, Launcher, Logout, NotifCenter, Calendar, StatusBar, Toasts).
- `services/` — LayoutState (состояние слотов/persist), SysMon (датчики), NotifStore.
- `kit/` — примитивы (Panel, Field, SegBar, Chip, Icon, GlitchFX…), Theme/Motion — токены.
- Один слот = одна панель; открытие — волной снизу 180ms, ghost-эхо слота, replace за 120ms.
