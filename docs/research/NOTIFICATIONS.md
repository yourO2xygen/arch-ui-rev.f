# Freedesktop Notifications: полный протокол и реализация notification daemon на Quickshell 0.3.2

Дата: 2026-11-01. Источники: spec v1.3 (18 Aug 2024) — specifications.freedesktop.org/notification-spec/latest/,
исходники quickshell (`src/services/notifications/`, склонирован master), доки mako/dunst.

---

## 1. Обзор протокола

- Имя сервиса на **сессионной** шине: `org.freedesktop.Notifications`
- Путь объекта: `/org/freedesktop/Notifications`
- Интерфейс: `org.freedesktop.Notifications`
- Версия спеки: 1.3 (2011+ → 1.2 добавил `image-data`/`image-path`/`resident`/`transient`/`action-icons`, 1.3 — правки текста)
- Сервер должен **захватить имя** `org.freedesktop.Notifications` на старте; клиент не обязан ждать активации.

Quickshell делает это автоматически при инстанцировании `NotificationServer`: регистрирует объект на пути
`/org/freedesktop/Notifications` и пытается взять имя; если имя занято другим демоном — молча ждёт
его unregistration и пробует снова (`QDBusServiceWatcher`, watch Unregistration). Отсюда важный вывод:
**если параллельно запущен dunst/mako — quickshell-сервер не получит уведомления и не ругнётся** (только
warning в логе). Надо проверять владельца имени (`qdbus org.freedesktop.DBus ... NameHasOwner` / `busctl --user status org.freedesktop.Notifications`).

---

## 2. Методы D-Bus (точные сигнатуры из XML quickshell)

```
method GetCapabilities    → out as capabilities
method Notify(s appName, u replacesId, s appIcon, s summary, s body, as actions, a{sv} hints, i expireTimeout) → out u id
method CloseNotification(u id)
method GetServerInformation() → out s name, s vendor, s version, s specVersion

signal NotificationClosed(u id, u reason)      // reason: 1 expired, 2 dismissed, 3 CloseNotification
signal ActionInvoked(u id, s actionKey)
signal ActivationToken(u id, s activationToken) // нестандартное расширение (xdg-activation / startup-id)
signal NotificationReplied(u id, s replyText)   // нестандартное расширение (пришло из swaync; поддержано quickshell)
```

### 2.1 Notify — все 8 параметров (задача говорит «12», фактически их 8 + return id)

| # | Параметр | Тип | Семантика |
|---|---|---|---|
| 1 | `app_name` | `s` | Человекочитаемое имя приложения, может быть пустым. Иногда клиенты шлют сюда ерунду/`""` — иконку тогда брать из `desktop-entry`. |
| 2 | `replaces_id` | `u` | 0 = новое уведомление; ≠0 = атомарно заменить существующее (без мигания). Если id не существует/уже закрыт — сервер обязан создать **новое** уведомление и вернуть новый id. |
| 3 | `app_icon` | `s` | URI `file://...` **или** имя иконки из freedesktop icon theme. Пустая строка = нет иконки. Это **не** произвольный путь: bare-путь по спеке — имя темы. |
| 4 | `summary` | `s` | Заголовок, одна строка, UTF-8 (~40 символов, сервер должен word-wrap). |
| 5 | `body` | `s` | Текст, может содержать markup (см. §7). Может быть пустым. |
| 6 | `actions` | `as` | Плоский массив пар `[id0, label0, id1, label1, ...]`. Чётные индексы — ключ, нечётные — локализованный текст. Ключ `"default"` — действие по клику на тело (не показывать как кнопку). **Спецификация позволяет нечётную длину? Нет** — но кривые клиенты её шлют. |
| 7 | `hints` | `a{sv}` | Значения обязательно обёрнуты в variant. См. §6. |
| 8 | `expire_timeout` | `i` | мс. `-1` = решает сервер (может зависеть от urgency), `0` = никогда, `>0` = мс от момента показа. |
| → | return `id` | `u` | `replaces_id ≠ 0` → вернуть тот же id. Иначе — новый уникальный, **всегда > 0** (инкрементный счётчик допустим). |

### 2.2 CloseNotification(u id)
Принудительно закрыть и убрать с экрана →emit `NotificationClosed(id, 3)`.
Спека: «если уведомления нет — вернётся пустой D-Bus error». Quickshell **тихо игнорирует** неизвестный id
(не шлёт error) — это отклонение от буквы спеки, но на практике безопасно; клиенты (Telegram) шлют close
по уже закрытым id очень часто.

### 2.3 GetServerInformation
Quickshell отвечает жёстко: `name="quickshell"`, `vendor="quickshell"`, `version=<версия quickshell>`,
`specVersion="1.2"`. **Кастомизировать нельзя** (захардкожено в `server.cpp`).

### 2.4 NotificationClosed — инварианты
- `reason`: 1 = expired, 2 = dismissed пользователем, 3 = `CloseNotification`, 4+ = зарезервировано.
- **Id инвалидирован ДО посылки сигнала** — после получения сигнала клиент не должен использовать id
  (в т.ч. слать на него actions-ответы).
- Сервер обязан послать `NotificationClosed` на любое закрытие: таймаут, клик, close-метод, replace
  (replace НЕ считается закрытием — id живёт).

### 2.5 ActionInvoked(u id, s action_key)
Шлётся при клике на тело (`default`) или на кнопку действия. Клиент **не** обязан уметь это слушать.
Ответственность сервера: послать сигнал **до** закрытия уведомления (иначе клиент получит ActionInvoked на
мёртвый id; формально id валиден в момент сигнала). Quickshell: `NotificationAction.invoke()` →
`ActionInvoked` → если `!resident` → `close(Dismissed)`. Правильный порядок соблюдён.

---

## 3. Capabilities — полный список и что реально заявлять

Стандартные значения (таблица 5 спеки):

| capability | смысл | Поддержка quickshell |
|---|---|---|
| `actions` | сервер показывает кнопки действий | ✅ свойство `actionsSupported` (default **false**) |
| `action-icons` | идентификаторы действий — имена иконок (per-notification hint `action-icons`) | ✅ `actionIconsSupported` (default false) |
| `body` | показ body | ✅ `bodySupported` (default **true**) |
| `body-markup` | markup в body (b/i/u/a/img) | ✅ `bodyMarkupSupported` (default false) |
| `body-hyperlinks` | `<a href>` | ✅ `bodyHyperlinksSupported` (default false) |
| `body-images` | `<img src>` | ✅ `bodyImagesSupported` (default false), но **рендерить `<img>` придётся самому** — quickshell просто отдаёт body строкой |
| `icon-static` | 1 кадр изображения | ✅ = свойство `imageSupported` (default false); quickshell маппит `imageSupported → "icon-static"` |
| `icon-multi` | анимация кадров | ❌ нет |
| `persistence` | уведомление живёт в фоне/в центре | ✅ флаг `persistenceSupported` (default false) — **только декларация**, хранение реализуете вы |
| `sound` | звук; обязывает поддержать `sound-file` и `suppress-sound` | ❌ нет. Если заявите через `extraHints` — придётся играть звук самому |
| `inline-reply` | (нестандартный, из swaync) быстрый ответ | ✅ `inlineReplySupported` (default false), сигнал `NotificationReplied` |
| `sync` / `append` | (gnome/kde extensions) | ❌ нет |
| `x-canonical-*` (private-*, secondary-icons, urgency? нет) | | ❌ нет |
| vendor caps `x-...` | | через `extraHints: QVector<QString>` — попадают в GetCapabilities как есть |

Логика `GetCapabilities()` в quickshell (`server.cpp:144`): собирает строки по флагам, в конце добавляет
`extraHints`. Итого **объявляйте capabilities ровно то, что реально делаете**: ложное `body-markup` без
парсинга = теги видны пользователю; ложное `actions` = клиенты шлют действия, кнопок нет, `ActionInvoked`
не приходит → в Telegram «отметить прочитанным» пропадает.

Рекомендуемый набор для полнофункционального демона:
`actions, action-icons (если рисуете иконки), body, body-markup, body-hyperlinks, icon-static, persistence, inline-reply`.
`sound` — только если реализуете воспроизведение (canberra/pw via `DesktopEntry`/hint).

---

## 4. urgency и expireTimeout — правила принятия решений (на вашей стороне QML!)

Quickshell **не** обрабатывает таймауты вообще: `Notification.expireTimeout` — просто прозрачно переданное
клиентом значение, и `expire()` вызвать должны вы. Ключевой нюанс исходников: свойство задокументировано
как «Time in **seconds**», но в `notification.cpp:115` кладётся сырое значение в **миллисекундах**
(`this->bExpireTimeout = expireTimeout;`). Считайте поле миллисекундами; это известное расхождение доки/кода.

Правила (спека + практика dunst/mako/swaync):
- `expireTimeout > 0` → уважать клиента (но многие клиенты шлют фиксированные 5-10с даже для critical — см. §9).
- `expireTimeout == 0` → никогда не истекает (но убирается по клику/дисмису).
- `expireTimeout == -1` → сервер решает. Рекомендация:
  - urgency **low** → 4–5 с;
  - urgency **normal** → 6–10 с;
  - urgency **critical** → **не истекает никогда** (спека прямо: «Critical notifications should not automatically expire»).
- `critical` (2) визуально: акцентная рамка/цвет, звук, не должен уходить в «тосты-очередь» ниже low/normal.
- DND (не беспокоить): critical обычно **пробивает** DND (как dunst `override_pause_level`, mako группировка
  по urgency); low/normal в DND уходят сразу в историю, тост не показывается.

Перечисления в QML: `NotificationUrgency.Low/Normal/Critical` (0/1/2),
`NotificationCloseReason.Expired/Dismissed/CloseRequested` (1/2/3) — singleton'ы с `toString()`.

⚠️ Парсинг urgency: `hints["urgency"]` приходит как variant-обёрнутый `BYTE`. Quickshell делает
`hints.value("urgency").value<NotificationUrgency::Enum>()`, при неудаче конверсии останется 0 (Low) →
это источник симптома «critical ведёт себя как low». Обязательно протестировать `notify-send -u critical`.
Если у вас воспроизводится — страховка: читать `notification.hints["urgency"]` самому
(`Number(hints.urgency)`) и хранить свою копию urgency.

---

## 5. Actions: default, action-icons, inline-reply, resident

- Массив пар. `default` — клик по телу; по конвенции его **не рисуют кнопкой**. Quickshell отдаёт его в
  `notification.actions` как обычный `NotificationAction { identifier: "default"; text: "..." }` — фильтруйте в UI.
- `action-icons` hint=true + cap `action-icons` → `NotificationAction.identifier` интерпретировать как icon name
  (freedesktop icon naming), `text` — только для accessibility/tooltip.
- **resident** (hint, bool): после `ActionInvoked` НЕ закрывать. Quickshell: `Notification.resident`;
  `invoke()` закрывает только если `!resident`. Для resident-уведомлений обязателен явный путь дисмиса.
- **inline-reply**: если клиент прислал action с ключом `inline-reply` (text = placeholder), и на сервере
  `inlineReplySupported: true` — quickshell **вынимает** его из `actions` и выставляет
  `hasInlineReply: true` + `inlineReplyPlaceholder: string`. Ответ: `notification.sendInlineReply(text)` →
  сигнал `NotificationReplied(id, text)` клиенту; если `!resident` — закрывается. Если
  `inlineReplySupported: false`, «inline-reply» остаётся обычным действием в списке — рисовать его кнопкой нельзя.
- Нечётная длина `actions` → quickshell warn и **игнорирует весь список** (`notification.cpp:219`).
- Дубликаты `inline-reply` → warn, берётся первый.

---

## 6. Hints — все стандартные (таблица 4 спеки)

| hint | тип | обработка в quickshell |
|---|---|---|
| `urgency` | BYTE | → `notification.urgency` (см. §4, предупреждение) |
| `category` | STRING | только в `hints` (js-объект). Формат `class.specific`: `call`, `call.incoming`, `call.ended`, `call.unanswered`, `device.added/error/removed`, `email.arrived/bounced`, `im.received/error`, `network.connected/disconnected/error`, `presence.online/offline`, `transfer.complete/error`. Полезно для группировки/иконок. |
| `desktop-entry` | STRING | → `notification.desktopEntry`; при пустом `app_icon` quickshell **сам** подставляет иконку из .desktop (`DesktopEntryManager.byId()`) в `appIcon` |
| `image-data` | (iiibiiay) | → `notification.image` (строка-URL для `Image {}`), приоритет 1 |
| `image_data` | (iiibiiay) | deprecated, тоже поддержан |
| `icon_data` | (iiibiiay) | deprecated (libnotify <1.1), тоже поддержан, приоритет 4 |
| `image-path` | STRING | → `notification.image`; если не `file:` — трактуется как icon-theme name через `IconImageProvider` |
| `image_path` | STRING | deprecated, поддержан |
| `resident` | BOOL | → `notification.resident` |
| `transient` | BOOL | → `notification.transient` — обходить persistence/центр (не сохранять в историю) |
| `sound-file` | STRING | ❌ не обрабатывается — на вас (если заявляете `sound`) |
| `sound-name` | STRING | ❌ аналогично (freedesktop sound naming, напр. `message-new-instant`) |
| `suppress-sound` | BOOL | ❌ на вас |
| `action-icons` | BOOL | → `notification.hasActionIcons` |
| `x`, `y` | INT32 | ❌ нет отдельного свойства; доступны в `notification.hints`. Подавляющее большинство демонов их игнорирует — можно тоже |
| `x-*` / приватные | — | доступны в `notification.hints` (QVariantMap, уже без больших бинарных image-хинтов — quickshell их вычищает) |

---

## 7. Markup, иконки, образы

### Markup (cap `body-markup`)
Разрешённые теги: `<b> <i> <u> <a href="..."> <img src alt>`. Ссылки — не замена actions; images ≤200x100,
только локальные файлы. Если cap не заявлён — сервер должен **вырезать** теги (в quickshell этого нет:
просто поставьте `Text { textFormat: Text.PlainText }` или `TextEdit`/`Text.MarkdownText`/Html при поддержке;
для клика по `<a href>` — `linkActivated`/`onLinkActivated` у `TextEdit`).

### Приоритет выбора картинки (если показываете одну)
1. `image-data` 2. `image-path` 3. `app_icon` 4. `icon_data` (совместимость).
Если рисуете и image и icon: icon = `app_icon`, image = `image-data` → `image-path` → `icon_data`.
Quickshell уже реализует этот приоритет для **своего** свойства `notification.image`
(image-data > image_data > icon_data > image-path), но `appIcon` отдельный — соблюдайте порядок в UI:
картинка из `image` важнее аватарки `appIcon` (например, аватар отправителя Telegram приходит именно image-data).

### app_icon
- `file:///path/to.png` — рендерить как file URL;
- `firefox`, `dialog-information` — имя из icon theme (`IconImage { }` quickshell или `Image` + `QIcon`);
- пусто → fallback на `desktop-entry` (quickshell делает сам), иначе плейсхолдер.

### image-data: точный формат `(iiibiiay)`
`width i, height i, rowstride i, has_alpha b, bits_per_sample i, channels i, data ay` (RGB byte order,
bits_per_sample == 8, channels 4 при alpha иначе 3).
⚠️ В `dbusimage.cpp` quickshell **строго** требует `rowstride == width*channels`, иначе warning — но данные
всё равно кладутся в QImage сrowstride = width*channels. Реальные клиенты (gdk-pixbuf) **выравнивают**
rowstride до 4 байт → картинка съедет по диагонали. Типичный случай: ширина 100, channels 4 → rowstride 400
(ок), но ширина 70 → реальный rowstride 280, а `width*4 = 280` (ок)... padding возникает при width не кратном:
напр. width 101×3=303 → реальный rowstride 304. Это классический баг «полосатых» аватарок. Если встретится —
можно перехватить: рендерить не через `notification.image`, а декодировать самому в QML нельзя; вариант —
патч/upstream issue, либо принять искажение (большинство клиентов шлют кратные размеры).
BGRA-vs-RGB: спека требует RGB; отдельные клиенты historically шлют BGR → «синие лица». На вашей стороне
лечится только патчем; редкость.

`notification.image` — готовая строка для `Image { source: notif.image }` (внутренний async image provider,
`QsIndexedImageHandle`).

---

## 8. Реализация в Quickshell 0.3.2 — точный API

Проверено по исходникам 0.3.x (`src/services/notifications/{qml,notification,server}.{hpp,cpp}`, `dbusimage.*`, `org.freedesktop.Notifications.xml`).

### `NotificationServer` (singleton-тип, `Quickshell.Services.Notifications`)

Свойства (все RW, default указан):
| Свойство | default | Влияние |
|---|---|---|
| `keepOnReload: bool` | true | перепосылать ли уведомления после reload; менять **до** старта сервера (иначе qCritical и игнор) |
| `persistenceSupported` | false | cap `persistence` |
| `bodySupported` | **true** | cap `body` |
| `bodyMarkupSupported` | false | cap `body-markup` |
| `bodyHyperlinksSupported` | false | cap `body-hyperlinks` |
| `bodyImagesSupported` | false | cap `body-images` |
| `actionsSupported` | false | cap `actions` |
| `actionIconsSupported` | false | cap `action-icons` |
| `imageSupported` | false | cap `icon-static` |
| `inlineReplySupported` | false | cap `inline-reply`; также **гейтит** распознавание inline-reply action |
| `trackedNotifications` (ro) | — | `ObjectModel<Notification>` — все текущие tracked уведомления |
| `extraHints: QVector<QString>` | [] | доп. строки в GetCapabilities |

Все supported-флаги можно менять и **после** старта (`updateSupported()` обновляет живой сервер) — но
клиенты перечитывают capabilities нечасто, поэтому задавайте сразу при создании.

Сигнал (главная точка входа):
```
signal notification(Notification notification)
```
Внутри обработчика **обязательно** решить судьбу: `notification.tracked = true` (оставить) или
`false`/ничего (уведомление будет закрыто с reason=Dismissed; `NotificationClosed` клиенту уйдёт
**после** возврата Notify через queued connection — deadlock'ов D-Bus нет, быстрый return безопасен).

### `Notification` (Retainable)

Read-only свойства: `id: quint32`, `lastGeneration: bool`, `actions: list<NotificationAction>`,
`hints: QVariantMap` (без image-* байтовых хинтов).
RW / биндимые: `tracked: bool` (false ⇒ = dismiss), `expireTimeout: qreal` (**мс**, вопреки доке — см. §4),
`appName, appIcon, summary, body: string`, `urgency: NotificationUrgency.Enum`, `hasActionIcons: bool`,
`resident: bool`, `transient: bool`, `desktopEntry: string`, `image: string` (URL для `Image{}`),
`hasInlineReply: bool`, `inlineReplyPlaceholder: string`.
`appIcon` — уже с fallback'ом на иконку desktop-entry; `""` если ничего не нашлось.

Методы:
- `expire()` — закрыть с reason Expired (послать клиенту NotificationClosed(id,1)).
- `dismiss()` — закрыть как Dismissed (2).
- `sendInlineReply(text: string)` — только если `hasInlineReply && inlineReplySupported`.
- `close(reason)` — внутренний (0 = re-track через `tracked = true`).

Сигнал `closed(reason)` — объект уничтожается сразу после выхода всех обработчиков ⇒ для истории
используйте attached property **`Retainable`**: `Retainable.lock()` удерживает объект, `unlock()`/`forceUnlock()`
отпускает (`Retainable.retained`, `retainedChanged`). Либо скопируйте данные в свою модель до закрытия
(рекомендую: копия в JSON-стор → persistence между перезапусками, чего Retainable не даёт).

### `NotificationAction`
`identifier: string` (icon name при hasActionIcons), `text: string` (RW — можно локализовать/подменить),
`invoke()` → `ActionInvoked` + авто-dismiss если `!resident`.

### Сигналы, которые уходят клиентам (генерирует quickshell)
`NotificationClosed(id, reason)`, `ActionInvoked(id, action)`, `NotificationReplied(id, replyText)`.
`ActivationToken` объявлен в XML, но **ничем не эмитится** — фокус-подъём приложений через xdg-activation
придётся делать самому (Hyprland: `hyprctl dispatch focuswindow`/`dispatch pin`… либо ничего).

### Поведение при reload конфига
`onPostReload` → `switchGeneration(keepOnReload)`:
- старые уведомления снимаются с tracked, помечаются `lastGeneration = true`, **заново эмитятся** в сигнал
  `notification()` — вы должны сами повторно выставить `tracked = true` для тех, что должны жить
  (отфильтровав по `lastGeneration`);
- не трекнутые → `NotificationClosed(id, Expired)` клиенту и delete;
- `trackedNotifications` меняется на новый инстанс модели (приходит `trackedNotificationsChanged`).
⇒ вся история должна жить в **вашем** сторе (JS/JSON), а не в `trackedNotifications`, иначе она теряется.

### Ограничения quickshell (проверено по коду)
- Нет звука, нет `append`/`sync`, нет `icon-multi`, нет `x/y-canonical` API (только raw hints), нет
  ActivationToken, нельзя кастомизировать `GetServerInformation`, нельзя отвечать D-Bus error на
  CloseNotification несуществующего id, нет per-notify приоритетов/группировок — всё это уровень QML-стора.
- `expireTimeout` в секундах в доке, реально мс.
- Парсинг image-data строгий к rowstride (§7).
- Нельзя получить тело/данные **понастоящему** сырого body markup-а отдельно от строки — рендерите сами.

---

## 9. Клиенты-отправители и типичные баги

### Кто и что шлёт
- `notify-send "Sum" "Body"` → `expire_timeout = -1`, urgency normal, без actions.
  Флаги: `-u critical|normal|low`, `-t 5000`, `-t 0`, `-r ID` (replaces), `-i icon`, `-A "key:Label"`
  (action + ждёт клика), `--transient`, `--app-name=...`, `-h STRING:KEY=VAL` (hint, напр.
  `-h int:x:100`, `boolean:TRANSIENT:true`, `byte:URGENCY:2`).
- `dunstify` — как notify-send + `-a`/`-I`/`-r`/action id возврат.
- **Браузеры** (Chromium/Firefox через libnotify/Web Notifications): шлют `image-data` (аватарки),
  `desktop-entry`, actions (`default` + иногда кнопки), resident для мессенджер-подобных; Chrome шлёт
  `x-canonical-*` на Ubuntu-сборках. Часто `app_name` = "Chromium", `summary` = заголовок страницы.
- **Telegram Desktop**: summary = имя чата, body = текст, image-data = аватар, action `default` →
  активация окна, `inline-reply`-подобного нет (только `default`); шлёт **свои** id в replace при
  последовательных сообщениях из одного чата только если включено в настройках.
- mpd-клиенты (mpdscribble, mpDris2), volume (playerctl/wob не dbus), KDE Connect, `pacman` hooks
  (шлют через `notify-send` в скриптах, часто пачками), `mobile.battery`-подобные.
- **Прогресс-бары**: клиенты типа `notify-send -h int:value` / transmission-daemon использует
  `expires`/`x-*`? — собственные хинты, доступные в `hints`.

### Топ источников багов в реализации (что ломается у всех)
1. **`replaces_id`-утечка / Zombie-тосты**: клиент шлёт replace на id, который сервер уже закрыл → сервер
   обязан создать НОВОЕ (quickshell делает верно: `idMap.value(replacesId)` → nullptr → новый id). Баг
   возникает в самописных серверах, которые возвращают 0 или reuse id. Обратный баг клиента: Telegram
   кэширует id и слит его в replace после перезапуска демона — сервер перезапустился, id-пространство
   началось с 1, чужой id → обновится чужое уведомление (коллизия id после рестарта). Mitigation:
   монотонный счётчик не сбрасывать в рамках сессии шины (у quickshell `nextId` живёт в процессе ⇒
   перезапуск процесса сбрасывает; нельзя перезапускать shell «под шумок» — см. §11).
2. **Critical исчезают**: (а) сервер сам выставляет таймаут по умолчанию для всего; (б) urgency-конверсия
   не сработала → Low; (в) клиент (браузер!) шлёт critical с `expire_timeout=5000` — по спеке клиент
   прав, но UX требует неистекающих critical: правило «critical ⇒ никогда не истекает» должно иметь
   приоритет над клиентским таймаутом (так делает dunst через urgency_critical timeout=0).
3. **Неверный argb/image-data парсинг**: rowstride padding (§7), порядок каналов, sample bits ≠ 8,
   `icon_data` (старый libnotify) не реализован; а также утечки: гигантские QByteArray в hints
   (quickshell уже вычищает image-хинты из `hints` — не держите свои копии).
4. **Действия после закрытия / потерянные ActionInvoked**: клик по кнопке → `ActionInvoked` →
   close; если тост уничтожен в UI до invoke (гонка с таймером авто-скрытия) — invoke не уйдёт никогда.
   Также: тост закрылся по таймеру, клиент ещё держит кнопки в центре уведомлений → клик должен либо
   работать (нужно, чтобы Notification был жив — Retainable.lock), либо кнопки прятать. Решение: кнопки
   в истории дублировать только для `persistence`-уведомлений и держать объект залоченным.
5. **Deadlock / missed CloseNotification извне**: `CloseNotification` приходит с id, которого нет
   (клиент услужливо закрывает закрытое) → сервер не должен падать/ошибить (quickshell ок). Обратная
   сторона: сервер шлёт `NotificationClosed` **изнутри** обработчика Notify (синхронно) → re-entrancy в
   клиенте (был реальный источник дедлоков у ранних swaync/lqc реализаций). Quickshell特意 шлёт queued —
   не ломайте это, если будете форкать.
6. Доп. наблюдённые: `transient`-уведомления от volume-OSD заспамливают историю (фильтровать в стор по
   `transient`), дубликаты одного сообщения каждые 5 с (коалировать по app+summary+body), `app_name`
   пустой у notify-send-скриптов, `app_icon` = bare path `/usr/share/...png` (не file://) — обрабатывать
   как файл тоже.

### Спам / перегрузка
100 уведомлений/сек (например, `while true; notify-send`): обязательно
- очередь тостов с лимитом видимых (mako `max-visible=5`);
- коалирование: same (app, summary, body, urgency) → заменить и счётчик «×N» (dunst `stack_duplicates`,
  `sort=update`);
- троттлинг рендера: батчить добавления в стор через `Qt.callLater`/таймер 50–100 мс;
- лимит истории (mako `max-history`, dunst `history_length=20`) + eviction;
- replace-шторм (прогресс-бары) — обновлять существующий тост по id, не создавать новый.

---

## 10. Сравнение с mako / dunst / swaync

| Аспект | mako | dunst | swaync | Куда двигаться вам |
|---|---|---|---|---|
| Таймаут -1 | `default-timeout` (default 0 = никогда) | urgency_* `timeout` (в типичном конфиге: low/normal 10s, critical 0 = никогда) | свои пресеты по urgency | low 5s, normal 8s, critical ∞ |
| Critical | expire по urgency-правилам | не истекает, приоритет сортировки | не истекает, «do-not-disturb» пробивает | то же |
| История | in-memory, `max-history=5`, `history=1` | `history_length=20`, dunstctl context menu | центр уведомлений + optional persist | свой JSON-стор, лимит ~200 |
| Resident | поддержан | поддержан | поддержан | через `resident` |
| Transient | не в историю при `history`? (сохраняется как expired) | bypass idle-pause | не сохраняется | не сохранять в историю |
| Inline-reply | поддержан (cap `inline-reply`, `NotificationReplied`) | нет | придумал | через quickshell `inlineReplySupported` |
| Actions | кнопки + `default` по клику | `(A)` индикатор, действия через dmenu | полноценные кнопки | кнопки + клик по телу = `default` |
| Картинки | image-data/path/icon_data, strict | то же | то же | quickshell даёт `image` |
| DND | через `makoctl mode` | pause via `dunstctl set-paused` | toggle, критичные пробивают | свой флаг + критичные пробивают |
| Persistence-флаг | нет (не заявляет) | нет | да (центр) | да — и реализовать центр |

---

## 11. Рекомендуемая архитектура

```
┌───────────────────────────────────────────────────────────────────┐
│ NotificationServer (D-Bus слой, quickshell)                        │
│  supported flags + обработчик `notification(notif)`                 │
│  → мгновенно: копия данных в NotificationStore, Retainable.lock()  │
└──────────────┬─────────────────────────────────────────────────────┘
               │ store.append(data)   (единственный мутатор)
┌──────────────▼─────────────────────────────────────────────────────┐
│ NotificationStore (JS-объект/синглтон)                             │
│  - records: [{id, appName, appIcon, summary, body, image, urgency, │
│     actions[], hints, transient, resident, hasInlineReply,         │
│     timestamp, replacedFrom, dupCount, state: toast|history|closed}]│
│  - persist: FileView JSON в ~/.cache/… (без transient)             │
│  - коалирование, лимиты, DND-логика, таймеры тостов                │
│  сигналы: toastAdded(record), toastUpdated(record),                │
│           toastRemoved(id), historyChanged(), dndChanged()         │
└──────┬───────────────────────────────┬──────────────────────────────┘
       │                               │
┌──────▼─────────────┐        ┌────────▼──────────────────────────┐
│ ToastLayer          │        │ NotificationCenter (панель)        │
│ верх-право, max 3–5 │        │ TODAY / YESTERDAY / раньше,         │
│ очередь + анимации  │        │ кнопки actions, inline-reply, DND,  │
│ клик → default      │        │ clear, per-app фильтры              │
└─────────────────────┘        └─────────────────────────────────────┘
```

Правила стора:
- **Toast-таймер**: per-record. `expireTimeout>0` → клиентское значение; `0` → не таймерить (но critical и
  так не истекает); `-1` → по urgency (5/8/∞). Пауза таймера при hover (как dunst `mouse_hover`).
- **DND**: `critical` показывать всегда; low/normal — только в историю (`state: history` сразу).
- **transient** — никогда не в persist и (опционально) не в историю.
- **Клик по телу** → action `default` (`invoke()`), иначе просто dismiss.
- **Действия в истории**: только если удержали Notification через `Retainable.lock()`; иначе кнопки скрывать.
- **Закрытие клиентом** (`CloseNotification`) quickshell делает сам: уведомление выпадает из
  `trackedNotifications`, у вас сработает `closed(CloseRequested)` → убрать тост и пометить в истории.
- **Перезапуск/раскатка**: при старте чистить просроченные записи из persist (TTL, напр. 7 дней).

Скелет QML:

```qml
NotificationServer {
    id: server
    persistenceSupported: true
    bodySupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    actionsSupported: true
    actionIconsSupported: false      // включайте только если рисуете иконки действий
    imageSupported: true
    inlineReplySupported: true

    onNotification: (notif) => {
        Store.accept(notif);          // копия данных + таймеры + DND-решение
        notif.tracked = true;         // иначе будет закрыт немедленно
    }
}
```

`Store.accept()` (псевдо):

```js
function accept(n) {
    const rec = {
        id: n.id, app: n.appName, icon: n.appIcon, summary: n.summary, body: n.body,
        image: n.image, urgency: n.urgency, transient: n.transient, resident: n.resident,
        actions: n.actions.map(a => ({ id: a.identifier, text: a.text })),
        hasInlineReply: n.hasInlineReply, placeholder: n.inlineReplyPlaceholder,
        hints: Object.assign({}, n.hints), ts: Date.now(), dup: 1
    };
    if (coalesce(rec)) return;                    // same app+summary+body → dup++
    // notification.raw = n  — если нужны действия/inline-reply, можно ещё и залочить
    if (dnd && rec.urgency !== NotificationUrgency.Critical) history.push(rec);
    else toasts.push(rec);
    if (!rec.transient) schedulePersist();
    if (rec.urgency !== NotificationUrgency.Critical) armToastTimer(rec, timeoutFor(rec));
    n.closed.connect(reason => Store.onClosed(rec, reason));
}
```

---

## 12. Чеклист тестов (воспроизводимые команды)

```bash
notify-send "Hello" "Body"                         # -1 таймаут, normal
notify-send -u critical "Battery" "5%"             # не должен истекать
notify-send -t 0 "Sticky" "never expires"          # явный never
notify-send -t 1 "Flash"                           # мгновенный таймаут
notify-send -r $(cat /tmp/id) -i dialog-information "Replaced"  # replace (сохраните id из GetCapabilities-теста)
notify-send -A ok1:OK -A cancel:Cancel -t 0 "Buttons"           # 2 кнопки, resident по -t 0
notify-send -A default:Activate "Click me"         # default action
notify-send -h boolean:TRANSIENT:true "Transient"  # не в историю
notify-send -h byte:URGENCY:2 -t 0 "Critical hint" # urgency через hint
notify-send -h int:X:100 -h int:Y:100 "Positioned" # x/y — должны просто игнорироваться
notify-send -i /usr/share/icons/.../firefox.png "Bare path icon"
notify-send -h string:sound-name:message-new-instant "Sound"
notify-send -u low "Low" "must be subtle"
dunstify -a test -I /path/img.png "ImageData"      # image через image-path
# спам-тест:
for i in $(seq 1 200); do notify-send "Spam $i" "body $i" -t 2000; done
# inline-reply-клиент: Firefox/Telegram либо python: dbus-send с action 'inline-reply'
```

Дополнительно проверить: перезапуск `quickshell` при живых уведомлениях (keepOnReload), reload конфига
(`qs -p config` лог: «Reloaded»), параллельный запуск dunst (имя занято), критичность при DND,
rowstride-кейс с шириной не кратной 4 (`-h` через python-gobject с gdk-pixbuf 101×3).

---

## 13. Открытые вопросы к пользователю (уточнить перед реализацией)

1. Нужен ли звук (`sound` cap + canberra/PipeWire) или звук играет сам клиент?
2. Inline-reply действительно нужен? (клиенты, которые его шлют: в основном Firefox/Telegram-форки; без него cap не заявлять)
3. Persist истории между перезапусками shell — да/нет, сколько дней/записей, где хранить (cache vs state dir)?
4. DND: manual toggle, авто-режим (fullscreen-детект через Hyprland `hyprctl activewindow`/`windowhandle` protocol), расписание?
5. Critical при DND: пробивать тостом, или только звук + бейдж?
6. Политика critical-таймаута: строго «никогда» или «никогда + красный, дисмис только кнопкой»?
7. Нужен ли per-app фильтр/приоритеты (как dunst rules по `app_name`/`desktop-entry`/`category`)?
8. Что делать с уведомлениями при блокировке экрана/idle (dunst `idle_threshold` — не истекать при idle)?
9. Хотите ли обход rowstride-бага патчем quickshell или считаем некритичным?
10. Клик по тосту при отсутствии `default` action — просто dismiss или открывать центр?
