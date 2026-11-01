# Уведомления: полный цикл

Сервер — `Quickshell.Services.Notifications` (D-Bus
`org.freedesktop.Notifications`), стор — services/NotifStore.qml (Singleton).
Шелл — единственный notification daemon в сессии.

## Цикл жизни уведомления

1. **Приём**: hint `urgency` (byte) разбирается вручную, fallback — **normal**.
   `transient`-уведомления (volume-OSD) никогда не персистятся и в историю не
   пишутся.
2. **Спам-гейт**: >10 уведомлений за 3s → свёртка «+N» (гейт применяется только
   к non-critical).
3. **Дедуп**: дубли по (app, summary, body) — счётчик «×N» на карточке; живое
   обновление карточки (QS не переэмитит `notification()` при replace —
   property-сигналы, паттерн `_connectLive`); окно «свежести» — 60s.
4. **Тосты** (верх-право, окно `archui:toasts`): стек до 4, новые сверху.
   - normal/low — исчезают по таймауту (low 5s, normal 8s; `expireTimeout`
     клиента уважается, hover — пауза таймера);
   - critical — не истекает сам, только вручную (клик/`dismissToasts`);
   - critical сверх стека → счётчик **«+N critical»**: клик открывает
     NotifCenter, при занятом слоте C — заменяет панель на месте
     (см. layout.md). Так 3 залипших critical не закрывают стек навсегда.
5. **История** (NotifCenter, слот C): все не-transient. Данные копируются в
   свой стор — JSONL `~/.cache/arch-ui/notifications.jsonl`, TTL 7 дней,
   лимит 200 записей, `bootId` разделяет сессии (TODAY/YESTERDAY по локальной
   дате). У записей из файла (после рестарта) кнопки действий скрыты —
   объектов-уведомлений больше нет. `Retainable.lock()` — только для
   уведомлений с действиями, unlock при удалении записи (TTL/лимит/Clear).
6. **replace_id** обновляет и тост, и запись истории без дублей;
   **CloseNotification** извне закрывает тост, история остаётся.

## DND

`qs -c shell ipc call archui dndToggle` (или `dnd true/false`). При DND:
low/normal — сразу в историю (тоста нет), critical — пробивает тостом.
Состояние персистится.

## Capabilities (что заявляем и чего нет)

Заявляем: `actions, body, body-markup, icon-static, persistence`.
**Не** заявляем и почему:

- `body-images` — raw image-data недоступен из QML, строгий rowstride-парсер QS
  не обойти; ложная capability дала бы «полосатые» аватарки;
- `inline-reply` — решение юзера (SPEC Q6): нет;
- `sound`, `append`, `action-icons` — нет.

Иконка уведомления: триада fallback — image → theme-icon (hasThemeIcon-гейт,
иначе маджента-заглушка) → inbox.

## Маска dunst — постоянная, зачем и как снять

`systemctl --user mask dunst.service` — выполнен и **оставляется навсегда**.
Зачем: если шелл упадёт (крах qs), D-Bus-имя `org.freedesktop.Notifications`
освободится и autostart-демон подхватит dunst — уведомления молча уйдут ему,
хотя наш шелл поднимется супервизором. Маска гарантирует, что никто, кроме
нас, имя не перехватит. Старый шелл тоже сам был notification daemon, dunst
никем не использовался.

Если когда-нибудь захочешь вернуть dunst:
`systemctl --user unmask dunst.service` — и тогда убирай автостарт qs или
мирись с конфликтом имени.

## Диагностика

```
notify-send "test" "body"                       # normal-тост
notify-send -u critical "crit" "body"           # критический, сам не истекает
notify-send -h string:x-canonical-private-synchronous:x "transient"  # в историю не пишется
qs log | grep -i notif
tail ~/.cache/arch-ui/notifications.jsonl
```

Повторное уведомление с тем же (app, summary, body) за минуту → «×2» на
карточке, а не новая.
