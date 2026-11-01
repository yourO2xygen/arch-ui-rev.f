# Quickshell 0.3.2 — справочник по API для полноценного desktop shell (Hyprland / Wayland)

Версия: **Quickshell 0.3.2 (revision , distributed by Arch Linux)**, Qt **6.12.0** (qt6-declarative 6.12.0-3).
Проверено на установленной системе (`qs --version`, `qs -h`) + локальные `.qmltypes` из
`/usr/lib/qt6/qml/Quickshell/**` (это точное описание типов данной сборки) + официальная документация
https://quickshell.org/docs/v0.3.2/ (зеркало quickshell.outfoxxed.me, версия v0.3.2 выбирается переключателем).

Обозначение уверенности:
- **[доки]** — подтверждено официальной документацией v0.3.2.
- **[qmltypes]** — подтверждено машинным описанием типов установленного пакета (точные имена/типы свойств, сигналов, методов).
- **[вывод]** — логический вывод / общие знания Qt, не найдено прямого подтверждения в доках.

---

## 0. CLI (`qs`) и жизненный цикл [доки, проверено `qs -h` на машине]

```
qs [OPTIONS] [SUBCOMMAND]
```

Опции:
- `-h, --help`, `-V, --version`
- `-n, --no-duplicate` — выйти немедленно, если инстанс **этого же конфига** уже запущен. Именно так делается «демон в единственном экземпляре»: `qs -c myshell -n -d`.
- `-d, --daemonize` — отвязаться от управляющего терминала.
- Выбор конфига (группа):
  - `-c, --config TEXT` (env `QS_CONFIG_NAME`) — имя конфига: `<xdg config dir>/quickshell/<name>/shell.qml`, напр. `~/.config/quickshell/myshell/` → `qs -c myshell`.
  - `-p, --path TEXT` (env `QS_CONFIG_PATH`) — путь к папке конфига или прямо к .qml файлу. Взаимоисключаем с `-c` и `-m`.
  - `-m, --manifest TEXT` — **[DEPRECATED]** манифест `$XDG_CONFIG_HOME/quickshell/manifest.conf`.
  - Если существует `<xdg>/quickshell/shell.qml` — он регистрируется как конфиг `default`, подпапки не рассматриваются.
- Логирование: `--no-color`, `--log-times`, `--log-rules TEXT` (формат `QT_LOGGING_RULES`), `-v`/`-vv`.
- Отладка: `--debug PORT:PORT` (QML debugger), `--waitfordebug`.

Сабкоманды:
- `qs log` — печать логов (работает и для демона).
- `qs list` — список запущенных инстансов (есть фильтры `--all`, `--newest`, `--any-display`).
- `qs kill` — убить инстансы.
- `qs ipc` — IPC (см. §5).
- `qs msg` — **[DEPRECATED]** → `qs ipc call`.

Входная точка конфига — **всегда `shell.qml`** в корне папки конфига. **Отдельного `shell.json` / манифеста с entry point в 0.3.2 НЕТ** — авторелоад включён по умолчанию (см. ниже), манифест `.conf` объявлен deprecated. [доки: guide/introduction, guide/distribution, guide/advanced]

### Горячая перезагрузка (reload) [доки]
- `Quickshell.watchFiles: bool` (по умолчанию `true`) — конфиг перезагружается при изменении любого файла. Отключение наблюдения: env `QS_DISABLE_FILE_WATCHER`.
- При reload создаётся **новое поколение (generation)** объектов: окна пересоздаются, обычное состояние QML **теряется**. Что сохраняется:
  - `PersistentProperties { reloadableId: "..." ; property bool expanderOpen: false }` — значения объявленных в нём свойств переживают reload (сигналы `loaded()` — всегда после reload-стадии, `reloaded()` — только если было что загружать). [доки]
  - `Retainable` / `RetainableLock` — механизм «удержания» объектов между поколениями (`Retainable.lock()/unlock()/forceUnlock()`, attached-свойство `Retainable.retained`, сигналы `dropped`, `aboutToDestroy`). Notification и др. — Retainable. [qmltypes, доки Notification]
  - `NotificationServer.keepOnReload: true` (по умолч.) — уведомления переиспускаются в новом поколении, у старых ставится `Notification.lastGeneration == true`. [доки]
  - Singleton'ы (`pragma Singleton` + `Singleton {}`) пересоздаются, но являются общими точками состояния внутри поколения.
- Всплывающее уведомление об ошибке reload: отключается env `QS_NO_RELOAD_POPUP` или из конфига `Quickshell.inhibitReloadPopup()`.
- Программный reload: `Quickshell.reload(hard: bool)`; сигналы `Quickshell.reloadCompleted`, `Quickshell.reloadFailed(errorString)`.
- Полезные env: `QS_CONFIG_PATH`, `QS_CONFIG_NAME`, `QS_APP_ID`, `QS_ICON_THEME`, `QS_DROP_EXPENSIVE_FONTS`, `QS_DISABLE_CRASH_HANDLER`, `QS_CRASHREPORT_URL`, `QS_NO_XINERAMA_STRUTS` (X11). [доки guide/advanced]

### Прагмы (комментарии `//@ pragma ...` в начале shell.qml) [доки guide/advanced]
`//@ pragma Internal` (не экспортировать файл из модуля) · `//@ if <js> / //@ endif` (условная компиляция, доступны `hasVersion(major, minor[, features])`, `hasQtVersion(major, minor)`, `env(name)`, `isEnvSet(name)`) · `//@ pragma Env VAR = VAL` / `DefaultEnv` (влияют только на сам Quickshell, не на дочерние процессы) · `//@ pragma UseQApplication` (QApplication вместо QGuiApplication, нужен для qqc2-desktop-style/KDE виджетов) · `//@ pragma NativeTextRendering` (Text.renderType=NativeRendering по умолчанию) · `//@ pragma IgnoreSystemSettings` · `//@ pragma RespectSystemStyle` (по умолчанию стиль QtQuick Controls принудительно Fusion) · `//@ pragma DropExpensiveFonts` (исключить woff/woff2) · `//@ pragma IconTheme <theme>` · `//@ pragma AppId <appid>` (appId окна/ленчера, свой значок для плавающих окон) · `//@ pragma ShellId <id>` · `//@ pragma DataDir|StateDir|CacheDir <dir>` (`$BASE/` = XDG base dir).

Рекомендация по запуску демона: в `hyprland.conf` → `exec-once = qs -c myshell -n -d` (или `qs -p ~/myshell -n -d`). [вывод на основе опций CLI]

---

## 1. Окна: PanelWindow / WlrLayershell / FloatingWindow / PopupWindow

Модуль: `import Quickshell` (PanelWindow, FloatingWindow, PopupWindow, QsWindow), `import Quickshell.Wayland` (WlrLayershell, WlrLayer, WlrKeyboardFocus). [qmltypes qmldir]

### 1.1 PanelWindow (`import Quickshell`) [доки + qmltypes]
Иерархия: `PanelWindow : QsWindow (WindowInterface)`; default property `data`.

```qml
import Quickshell
import QtQuick

PanelWindow {
  anchors { top: true; left: true; right: true }
  implicitHeight: 30
  screen: modelData          // из Variants
  color: "transparent"
  Text { anchors.centerIn: parent; text: "hi" }
}
```

Собственные свойства PanelWindowInterface [qmltypes]:
- `anchors : Anchors` — групповое свойство `left, right, top, bottom : bool` (по умолчанию все false — «чтобы не перекрыть экран из-за ошибки конфига» [доки]). Два противоположных якоря → размер по этой оси принудительно равен экрану (плюс margins). **Без якорей окно не прицеплено к краям и ведёт себя как плавающее окно слоя (floating layer-surface)** — размер задаётся `implicitWidth/implicitHeight` (или width/height). [доки: примечание про anchors; поведение при 0 якорях — вывод]
- `margins : Margins` — `left, right, top, bottom : int`; применяются **только к заанкеренным сторонам** [доки].
- `exclusiveZone : int` — резерв места под панель относительно якорей; установка переключает `exclusionMode` в `Normal`. **1 или 3 якоря обязательны**, иначе зона не действует [доки].
- `exclusionMode : ExclusionMode` — enum `ExclusionMode.Normal | Ignore | Auto` (Auto по умолчанию: зона вычисляется из размера окна). [qmltypes + доки]
- `aboveWindows : bool` (default true) — на Wayland маппится на `WlrLayershell.layer` [доки].
- `focusable : bool` (default false) — на Wayland маппится на `WlrLayershell.keyboardFocus` [доки].

Унаследовано от `QsWindow` / `ProxyWindowBase` [qmltypes]:
- `visible : bool`, `implicitWidth/implicitHeight : int`, `width/height : int`, `devicePixelRatio : double (ro)`, `screen : ShellScreen`, `color : QColor` (фон окна; `"transparent"` + Rectangle с radius = скруглённое окно [доки FAQ]), `mask : Region` (регион, принимающий ввод — всё вне маски кликается «насквозь»), `surfaceFormat : QsSurfaceFormat` (`opaque : bool` — Quickshell сам делает surface непрозрачным, если фон непрозрачный; для переключения прозрачности задайте `surfaceFormat.opaque: false` [доки FAQ]), `updatesEnabled : bool`, `contentItem : QQuickItem (ro)`, `windowTransform (ro)`, `backingWindowVisible (ro)`.
- Сигналы: `closed()`, `resourcesLost()`, `windowConnected()`, `visibleChanged()`, `screenChanged()`, `widthChanged()`, `heightChanged()`, `colorChanged()`, `maskChanged()`, `polished()` и др.
- Методы: `mapFromItem(item, point|x,y[,w,h]) : QPointF/QRectF`, `itemPosition(item)`, `itemRect(item)`.
- attached-объект `QsWindow.window` / `QsWindow.contentItem` (для доступа из любого Item к его окну). [qmltypes attachedType]

### 1.2 WlrLayershell (`import Quickshell.Wayland`) [доки + qmltypes]
Отдельный тип окна `WlrLayershell : ProxyWindowBase` **и одновременно attached-объект для PanelWindow** (рекомендуемый путь — PanelWindow + attached):

```qml
PanelWindow {
  WlrLayershell.layer: WlrLayer.Bottom          // attached syntax
  WlrLayershell.namespace: "myshell:bar"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
}
// динамически, кроссплатформенно:
PanelWindow {
  Component.onCompleted: if (this.WlrLayershell != null) this.WlrLayershell.layer = WlrLayer.Bottom;
}
```

Свойства [qmltypes]:
- `layer : WlrLayer` — enum `WlrLayer.Background | Bottom | Top | Overlay`; default **Top**. (`aboveWindows=false` ≡ `Bottom`, `true` ≡ `Top`.)
- `keyboardFocus : WlrKeyboardFocus` — enum `WlrKeyboardFocus.None | Exclusive | OnDemand`; default **None**. (Exclusive — перехват всего ввода клавиатуры для ленчера/лока; OnDemand — фокус по клику.)
- `namespace : string` — «аналог class у окон», для внешних правил (hyprland windowrule v2 по `namespace:`). **Нельзя менять после `windowConnected`** [доки].
- Плюс все свойства PanelWindow: `anchors`, `margins`, `exclusiveZone`, `exclusionMode`, `aboveWindows`, `focusable`.

Hyprland 0.57 поддерживает zwlr_layer_shell_v1 → всё это работает. [вывод/условие задачи]

### 1.3 FloatingWindow (`import Quickshell`) — обычное (не layer) окно [qmltypes; в 0.3.2 присутствует]
`FloatingWindowInterface : WindowInterface`, default property `data`. Свойства: `title : string`, `minimumSize/maximumSize : QSize`, `minimized : bool`, `maximized : bool`, `fullscreen : bool`, `parentWindow : QObject`; методы `startSystemMove() : bool`, `startSystemResize(edges : Qt.Edges) : bool`; плюс всё из QsWindow. Используется для «настоящих» окон shell (пример в доках IpcHandler именно с FloatingWindow). Это xdg_toplevel — Hyprland будет его тайлить по своим правилам (можно исключить windowrule по `class:` = AppId). [qmltypes; поведение — вывод]

### 1.4 PopupWindow (`import Quickshell`) [qmltypes]
`ProxyPopupWindow : ProxyWindowBase` — всплывающее окно, привязанное к родительскому (xdg_popup на Wayland):
- `parentWindow : QObject`, `relativeX/relativeY : int`, `anchor : PopupAnchor (ro)` — объект с `window`, `item`, `rect : Box`, `margins : Margins`, `edges : Edges.Flags`, `gravity : Edges.Flags`, `adjustment : PopupAdjustment.Flags` (`None|SlideX|SlideY|Slide|FlipX|FlipY|Flip|ResizeX|ResizeY|Resize|All`), метод `updateAnchor()`; `grabFocus : bool`, метод `reposition()`.
- `Edges` enum: `None, Top, Left, Right, Bottom`.
- Для меню есть высокоуровневое `QsMenuAnchor { menu: someHandle; anchor.item: button }`, `open()/close()`, `visible`. [qmltypes]

### 1.5 Мульти-монитор — Variants [доки guide/introduction]
```qml
Variants {                       // import Quickshell
  model: Quickshell.screens
  PanelWindow {
    required property ShellScreen modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
  }
}
```
Окна создаются/уничтожаются при подключении/отключении мониторов (реактивно на `Quickshell.screens`).

---

## 2. Quickshell.Services.Notifications — сервер уведомлений

Модуль: **`import Quickshell.Services.Notifications`** [qmltypes qmldir].

Типы: `NotificationServer`, `Notification`, `NotificationAction`, `NotificationUrgency`, `NotificationCloseReason`.

### NotificationServer [qmltypes + доки]
Прототип `PostReloadHook`. Реализует freedesktop Desktop Notifications Specification **серверную сторону**: Quickshell сам регистрирует имя `org.freedesktop.Notifications` на сессионной шине и сам отвечает на `GetCapabilities`/`CloseNotification` (методов `CloseNotification`/`GetCapabilities` в QML нет — рекламируемые возможности управляются свойствами ниже). [доки: «An implementation of the Desktop Notifications Specification»; устройство D-Bus — вывод]

Свойства (все read/write, управляют тем, что сервер рекламирует в GetCapabilities; по умолчанию почти всё `false`, `bodySupported` — `true`):
- `keepOnReload : bool` = true — переиспускать уведомления после reload (старым ставится `lastGeneration`).
- `persistenceSupported : bool` = false — «может держать уведомления в фоне/истории».
- `bodySupported : bool` = true
- `bodyMarkupSupported : bool` = false — если не хотите рендерить разметку, ставьте `Text.textFormat: Text.PlainText` и не включайте.
- `bodyHyperlinksSupported : bool` = false
- `bodyImagesSupported : bool` = false
- `actionsSupported : bool` = false
- `actionIconsSupported : bool` = false
- `imageSupported : bool` = false (большие картинки, напр. скриншоты)
- `inlineReplySupported : bool` = false
- `extraHints : list<string>` — дополнительные имена hints, передаваемые клиентам.
- `trackedNotifications : ObjectModel<Notification>` (readonly) — все отслеживаемые уведомления; готовая модель для «центра уведомлений».

Сигнал: `notification(Notification notification)` — получено уведомление. **Чтобы не выбросить, установите `notification.tracked = true`** (иначе будет отклонено). [доки]

### Notification (uncreatable, Retainable) [qmltypes + доки]
- `id : int (ro)` — id, выданный клиенту.
- `tracked : bool` — false = dismiss (эквивалент `dismiss()`).
- `lastGeneration : bool (ro)` — из предыдущего поколения (после reload).
- `expireTimeout : double (ro)` — **в секундах**, сколько валидно уведомление.
- `appName : string (ro)`, `appIcon : string (ro)` (иконка или из desktop entry, иначе `""`), `summary : string (ro)`, `body : string (ro)`.
- `urgency : NotificationUrgency (ro)` — enum `Low | Normal | Critical` (реализация флага `synchronous`/hints — на вам).
- `actions : list<NotificationAction> (ro)`; `hasActionIcons : bool (ro)`; `resident : bool (ro)` (не уничтожать после invoke действия); `transient : bool (ro)`; `desktopEntry : string (ro)`; `image : string (ro)` (картинка, напр. аватар).
- `hasInlineReply : bool (ro)`, `inlineReplyPlaceholder : string (ro)`.
- `hints : QVariantMap/js object (ro)` — все hints от клиента.
- Методы: `expire()` (закрыть как «истёкло»), `dismiss()` (закрыть как «закрыто пользователем»), `sendInlineReply(replyText : string)`.
- Сигналы: `closed(NotificationCloseReason reason)` — объект уничтожается после выхода из обработчика; а также `*Changed` по каждому свойству.

### NotificationAction [qmltypes]
`identifier : string (ro)`, `text : string (ro)`, метод `invoke()`, сигнал `textChanged`.

### NotificationCloseReason [qmltypes]
enum `Expired | Dismissed | CloseRequested`; статический `toString(value)`.

### Что если запустить второй демон?
Имя `org.freedesktop.Notifications` на шине одно: пока Quickshell-инстанс жив, второй демон (mako/dunst и т.п.) не сможет стать владельцем и не получит уведомления (стандартное поведение D-Bus; обычно демон при этом падает с ошибкой или молчит). При reload'е Quickshell держит имя (keepOnReload относится к переиспусканию уведомлений; само имя не отпускается). **[вывод — общие семантики D-Bus, в доках Quickshell явно не описано]**

Пример скелета:
```qml
import Quickshell
import Quickshell.Services.Notifications

Scope {
  NotificationServer {
    actionsSupported: true
    bodyMarkupSupported: true
    persistenceSupported: true
    inlineReplySupported: true
    imageSupported: true

    onNotification: (notif) => {
      notif.tracked = true;              // удерживаем
      // toast: показать окно; по истечении notif.expireTimeout*1000 → notif.expire()
    }
  }
}
```

---

## 3. Quickshell.Io — процессы, файлы, сокеты, IPC

Модуль: **`import Quickshell.Io`**.

### Process [qmltypes + доки FAQ/introduction]
- Свойства: `command : list<string>` (shell НЕ используется: `["sh","-c","..."]` для шелла), `workingDirectory : string`, `environment : QVariantHash` (дополнение к окружению), `clearEnvironment : bool`, `stdout : DataStreamParser`, `stderr : DataStreamParser`, `stdinEnabled : bool`, `running : bool` (присвоение true запускает), `processId : QVariant (ro)`.
- Парсеры stdout/stderr (вместо них `stdout: StdioCollector {}`):
  - `SplitParser { splitMarker: "\n" }` — сигнал **`read(string data)`** (унаследован от DataStreamParser) на каждый кусок; для долгоживущих потоков ( syrup IPC WM ).
  - `StdioCollector { onStreamFinished: ... }` — свойства `text : string (ro)`, `data : QByteArray (ro)`, `waitForEnd : bool`; сигналы `streamFinished()`, `dataChanged()`.
  - `DataStreamParser` базовый: сигнал `read(string data)`. `DataStream { parser: DataStreamParser }` — обёртка потока с `onBytesAvailable`.
- Сигналы: `started()`, `exited(int exitCode, QProcess::ExitStatus exitStatus)`, `runningChanged()`, `processIdChanged()` и `*Changed` остальных.
- Методы: `exec(command : list<string>)`, `exec(ProcessContext)` (`ProcessContext { command; environment; clearEnvironment; workingDirectory; unbindStdout }`), `signal(int signal)` (послать сигнал процессу), `write(string data)` (в stdin), `startDetached()` (запустить отсоединённо; Process продолжает жить? — эквивалент `Quickshell.execDetached`) [qmltypes; семантика частично вывод].
- Служебные сигналы QProcess-обёртки (ошибки): `onErrorOccurred(QProcess::ProcessError)` — enum `FailedToStart, Crashed, Timedout, ReadError, WriteError, UnknownError`.

### FileView (`import Quickshell.Io`) [qmltypes (QML-обёртка FileView.qml) + доки]
Чтение/запись небольших файлов; default property `adapter`.
- Свойства: `path : string` (или URL; пустая строка = выгрузить), `preload : bool` = true, `blockLoading : bool` = false (блокирующе дочитать при первом обращении — использовать только для конфигов до отрисовки окон), `blockAllReads : bool` = false, `printErrors : bool` = true, `watchChanges : bool` = **false по умолчанию** — при true дёргает `fileChanged()` при изменении файла на диске (типичный паттерн: `watchChanges: true; onFileChanged: this.reload()`), `atomicWrites : bool` = true, `blockWrites : bool` = false, `adapter : FileViewAdapter`, `loaded : bool (ro)`.
- Функции: `text() : string`, `data() : ArrayBuffer`, `reload()`, `setText(text)`, `setData(data)`, `writeAdapter()`, `waitForJob() : bool`.
- Сигналы: `fileChanged()`, `loaded()`, `loadFailed(FileViewError)`, `saved()`, `saveFailed(FileViewError)`, `adapterUpdated()`.
- `FileViewError` enum: `Success, Unknown, FileNotFound, PermissionDenied, NotAFile`.
- **JsonAdapter** (default): `"выключает" text/data и превращает содержимое JSON в свойства` — объявляете внутри `JsonAdapter { property color accent: "red"; property int count: 0 }`, значения автоматически читаются из файла и пишутся обратно через `writeAdapter()` (внутренний `JsonObject` прототип). Подходит для persist-конфига шелла. [доки FileView: «Currently the only adapter is JsonAdapter»; механизм свойств — docs JsonAdapter/qmltypes]

### Socket / SocketServer [qmltypes]
- `Socket { path: string; connected: bool; ... }` — unix local socket клиент; методы `write(string)`, `flush()`; сигнал `error(QLocalSocket::LocalSocketError)`; унаследован от `DataStream` → `parser : DataStreamParser` + сигнал `read(string)`. Используется, напр., для `~/.local/share/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` / `.socket2.sock`, если нужен сырой доступ (но для Hyprland есть готовый модуль).
- `SocketServer { path; active : bool; handler : Component }` — локальный сервер сокета (каждое подключение инстанцирует handler).

### IpcHandler — см. §5.

---

## 4. Quickshell (ядро) — синглтон `Quickshell`, утилиты

Модуль: **`import Quickshell`**. `Quickshell` — flag singleton (свойства/функции доступны без инстанцирования). [доки + qmltypes]

Свойства:
- `processId : int (ro)`, `instanceId : string (ro)` (для `qs ipc -i`), `shellId : string (ro)`, `appId : string (ro)`, `launchTime : QDateTime (ro)`.
- `screens : list<ShellScreen> (ro)` — текущие мониторы, реактивно; сигнал `screensChanged()`.
  `ShellScreen` (=QuickshellScreenInfo): `name, model, serialNumber : string (ro)`, `x, y, width, height : int (ro)`, `scale/devicePixelRatio : double (ro)`, `physicalPixelDensity, logicalPixelDensity (ro)`, `orientation, primaryOrientation (ro)`, `toString()`.
- `shellDir : string (ro)` — папка конфига (deprecated синонимы `configDir`, `shellRoot`).
- `workingDirectory : string` (чтение/запись), `watchFiles : bool` (авто-reload, default true).
- `clipboardText : string` — системный буфер. **ВНИМАНИЕ (доки): под Wayland буфер будет пуст, пока не сфокусировано окно quickshell.**
- `dataDir/stateDir/cacheDir : string (ro)` — `~/.local/share|~/.local/state|~/.cache/quickshell/by-shell/<shell-id>`; переопределяются прагмами.

Функции:
- `env(variable : string) : QVariant` — значение env или `null`.
- `execDetached(command : list<string>)` / `execDetached(context : ProcessContext)` — запустить процесс, отсоединённый от Quickshell (переживёт reload/выход); эквивалент `Process.startDetached()`; контекст: `{command: [...], environment: {...}, clearEnvironment: bool, workingDirectory: string}`. Без шелла: `["sh","-c", cmd]`. [доки]
- `iconPath(icon : string, check/fallback...) : string` — 3 перегрузки: (icon) — рисует фиолетовый квадрат если нет, (icon, fallback) — свой fallback, (icon, check:false) — вернёт `""`; `hasThemeIcon(icon) : bool`. Тема — `//@ pragma IconTheme <name>` или `QS_ICON_THEME`.
- `shellPath(path)/configPath(path)(deprecated)/dataPath(path)/statePath(path)/cachePath(path) : string`.
- `reload(hard : bool)`, `inhibitReloadPopup()`, `hasVersion(major, minor[, features]) : bool`, `hasQtVersion(major, minor) : bool`.
- Сигналы: `lastWindowClosed()`, `reloadCompleted()`, `reloadFailed(errorString : string)`, `screensChanged()`, `clipboardTextChanged()`.
- `QuickshellSettings { workingDirectory; watchFiles }` — доступ через `ShellRoot.settings`. [qmltypes]

**НЕ существует в 0.3.2** (проверено по qmltypes и сайдбару доков v0.3.2): `Quickshell.desktops`, `Uuid`, встроенного `Taskbar`. (Они появились в более новых версиях/вам не нужны: десктопы/воркспейсы — через `Quickshell.Hyprland`; список окон — `Hyprland.toplevels` или `ToplevelManager`, см. §10.)

### Прочие полезные типы ядра (`import Quickshell`)
- `Scope {}` — невизуальный контейнер (ReloadPropagator), аналог Item без визуала; рекомендован для размещения Process/Timer/Variants. [доки]
- `ShellRoot {}` — корень shell.qml (не обязателен, но даёт `.settings`). `Singleton {}` — корень для `pragma Singleton` файлов. [доки]
- `Variants { model; delegate (default); instances (ro) }` — см. §1.5. [qmltypes]
- `LazyLoader { active/loading/activeAsync/item/component/source }` — ленивое создание **не-Item** объектов (для Item-деревьев — стандартный `Loader`); главный инструмент экономии памяти. [доки FAQ + qmltypes]
- `BoundComponent { sourceComponent/source; bindValues; item }` — создание компонента с пробросом значений. [qmltypes]
- `PersistentProperties {}` — см. §0. `Reloadable { reloadableId }` — база для reload-логики.
- `Retainable` (attached), `RetainableLock { object; locked; retained }` — удержание объектов между поколениями. [qmltypes]
- `ScriptModel { values : list; objectProp : string; comparisonMode : ObjectComparison.Identity|Structure }` — QAbstractListModel из JS-массива (отлично для ListView с вычисляемыми моделями). [qmltypes]
- `ObjectModel` (внутр. `UntypedObjectModel`) — **read-only** модель из `values : list<QObject>`, `indexOf(obj)`, сигналы `objectInsertedPre/Post`, `objectRemovedPre/Post`; создаётся самим Quickshell для `trackedNotifications`, `Hyprland.toplevels` и т.п. Свои объекты из QML в него не добавить — используйте `ScriptModel` или QtQuick `ListModel`. [qmltypes + вывод]
- `SystemClock { enabled; precision : Hours|Minutes|Seconds; date : QDateTime (ro); hours/minutes/seconds : uint (ro) }` — правильный источник времени для часов (`precision: SystemClock.Minutes` экономит батарею). [доки + qmltypes]
- `ElapsedTimer {}` — `elapsed()/restart()` (сек, double), `elapsedMs/restartMs`, `elapsedNs/restartNs`. [qmltypes]
- `EasingCurve { curve : QEasingCurve }` — `valueAt(x)`, `interpolate(x, a, b)` (числа/точки/прямоугольники). [qmltypes]
- `ColorQuantizer { source : url; depth; imageRect; rescaleSize; colors : list<color> (ro) }` — доминирующие цвета картинки (обложки MPRIS и т.п.). [qmltypes]
- `DesktopEntries { applications : ObjectModel; byId(id) : DesktopEntry; heuristicLookup(name) }`, `DesktopEntry { id, name, genericName, startupClass, noDisplay, comment, icon, execString, command : list<string>, workingDirectory, runInTerminal, categories, keywords, actions : list<DesktopAction>; execute() }` — ленчер по .desktop-файлам. [qmltypes]
- `Region {}` — маска ввода окна: `shape : RegionShape.Rect|Ellipse`, `intersection : Intersection.Combine|Subtract|Intersect|Xor`, `item`, `x/y/width/height`, `radius` и покомпонентные радиусы, вложенные `regions`. Присваивается `QsWindow.mask`. [qmltypes]
- `QsMenuEntry / QsMenuOpener / QsMenuAnchor / QsMenuHandle / DBusMenu*` — меню (трей, leighton). `SystemTray` (`import Quickshell.Services.SystemTray`): `SystemTray.items`, `SystemTrayItem { id, title, icon, status, category, onlyMenu, ...; hasMenu; menu: QsMenuHandle; activate(); secondaryActivate(); scroll(delta, horizontal) }` — для трея. [qmltypes]

Таймеры: используется стандартный **`Timer` из `import QtQuick`** (`interval`, `running`, `repeat`, `onTriggered`). Типа `Interval` в Quickshell нет (есть `SystemClock.precision`). [доки]

---

## 5. IPC — IpcHandler и `qs ipc`

Модуль: **`import Quickshell.Io`**, тип `IpcHandler`. [доки + qmltypes]

```qml
IpcHandler {
  target: "launcher"                 // уникальное имя таргета
  function toggle(): void { launcherVisible = !launcherVisible }
  function open(query: string): void { ... }       // типы аргументов ОБЯЗАТЕЛЬНЫ
  function getQuery(): string { return query }

  signal queryChanged(newQuery: string)            // сигналы: 0 или 1 аргумент
}
```

- Свойства: `enabled : bool` (default true), `target : string` (уникально, можно менять в рантайме). [qmltypes/доки]
- Функции вызываются через CLI; ограничение: ≤10 аргументов; **типы аргументов и возвращаемого значения должны быть указаны явно, иначе функция не зарегистрируется**. Разрешённые типы: `string, int, bool, real, color` (возврат: `void` тоже). [доки]
- CLI:
  - `qs ipc show [-c конфиг] [-i id] [--pid N] [-n(newest)]` — список таргетов/функций.
  - `qs ipc call <target> <function> [args...]`, напр. `qs ipc call launcher toggle`.
  - `qs ipc wait <target> <signal>` — дождаться одного срабатывания сигнала.
  - `qs ipc listen <target> <signal>` — слушать сигнал постоянно.
  - `qs ipc prop get ...` — чтение свойств IPC-совместимых типов.
- Сигналы IpcHandler можно эмитить изнутри: `this.queryChanged(value)` (см. пример в доках IpcHandler).
- Это же — штатный способ «открыть/закрыть окно командой» вместо hyprland dispatch. [доки FAQ]

Внутренняя сигнатура обработчика: `onSignalTriggered(signal : string, value : string)`. [qmltypes]

---

## 6. Глобальные хоткеи + Hyprland

Модуль: **`import Quickshell.Hyprland`** (объединяет подплагины `_Ipc`, `_FocusGrab`, `_GlobalShortcuts`, `_SurfaceExtensions`). [qmltypes qmldir]

### GlobalShortcut (`import Quickshell.Hyprland`) [доки + qmltypes]
**Это НЕ регистрация произвольных клавиш из QML без hyprland.conf.** Реализован протокол `hyprland_global_shortcuts_v1` (в обход xdg-desktop-portal-hyprland, XDPH не нужен). Ключевая комбинация всё равно назначается в `hyprland.conf`:

```
# hyprland.conf
bind = SUPER, Space, global, quickshell:launcher   # <appid>:<name>
```

```qml
import Quickshell.Hyprland

GlobalShortcut {
  appid: "quickshell"        // default "quickshell"; нельзя менять в рантайме
  name: "launcher"           // нельзя менять в рантайме
  description: "Open app launcher"   // видно в `hyprctl globalshortcuts`

  onPressed:  { ... }
  onReleased: { ... }
  // pressed : bool (ro) — удерживается ли
}
```
- Свойства: `appid, name, description, triggerDescription : string` (последний «можно игнорировать» [доки]), `pressed : bool (ro)`.
- Сигналы: `pressed()`, `released()`, `pressedChanged()`.
- Предупреждение доков: пары appid+name уникальны на протоколе; внутри одного инстанса quickshell дубли обрабатываются, но **два инстанса quickshell/другие клиенты с тем же appid:name — тот, кто зарегистрируется последним, уронит композитор/клиент (краш)**.
- Вывод: для «хоткеев без hyprland.conf» альтернатива — обычные `bind = ..., exec, qs ipc call ...` через IpcHandler; полностью без hyprland.conf глобальных клавиш Wayland не даёт. [вывод]

### Hyprland (синглтон, `import Quickshell.Hyprland`) [qmltypes]
- Свойства: `focusedMonitor : HyprlandMonitor (ro)`, `focusedWorkspace : HyprlandWorkspace (ro)`, `activeToplevel : HyprlandToplevel (ro)`, `monitors / workspaces / toplevels : ObjectModel (ro)`, `requestSocketPath / eventSocketPath : string (ro)`, `usingLua : bool (ro)` (новое в 0.3.x — поддержка Hyprland Lua).
- Методы:
  - `dispatch(request : string)` — сырая dispatch-команда: `Hyprland.dispatch("workspace r+1")`, `Hyprland.dispatch("focuswindow address:" + toplevel.address)` и т.д.
  - `monitorFor(screen : ShellScreen) : HyprlandMonitor` — монитор по экрану Quickshell.
  - `refreshMonitors() / refreshWorkspaces() / refreshToplevels()`.
- Сигнал `rawEvent(HyprlandEvent event)` — все события event-сокета; `HyprlandEvent { name : string (ro); data : string (ro); parse(argumentCount : int) : list<string> }`.

Объекты:
- `HyprlandMonitor`: `id : int, name, description : string, x, y, width, height : int, scale : double, activeWorkspace : HyprlandWorkspace, focused : bool, lastIpcObject : QVariantMap` (все ro, с `*Changed`).
- `HyprlandWorkspace`: `address : string, id : int, name : string, active, focused, urgent, hasFullscreen : bool, monitor : HyprlandMonitor, toplevels : ObjectModel, lastIpcObject`; **метод `activate()`** — переключиться на воркспейс.
- `HyprlandToplevel`: `address : string, title : string, activated : bool, urgent : bool, workspace : HyprlandWorkspace, monitor : HyprlandMonitor, wayland : Toplevel, handle, lastIpcObject`; attached-тип. Метода `activate()` нет — фокус окна: `Hyprland.dispatch("focuswindow address:" + tl.address)`. [qmltypes; вывод по отсутствию метода]
- `HyprlandFocusGrab { active : bool; windows : list<QObject>; signal cleared() }` — захват клавиатуры между своими окнами (закрытие ленчера по клику мимо). [qmltypes]
- `HyprlandWindow` (attached): `opacity : double`, `visibleMask : Region` — управление прозрачностью/маской видимости **своего** layer-окна на уровне композитора. [qmltypes]

---

## 7. Производительность / демон — сводка рекомендаций [доки FAQ/advanced + вывод]

- **Один процесс на весь shell** (панель+ленчер+уведомления). «Процесс на виджет» — нет, сильно дороже по памяти. [доки FAQ]
- **Loader / LazyLoader** для всего, что не показано постоянно (ленчер, центр уведомлений, OSD) — главная экономия памяти и стартового времени. [доки FAQ]
- **SystemClock.precision: Minutes**, если секунды не показываются. [доки]
- Повторяющиеся по экранам вещи (Process/Timer/источники данных) выносить из Variants-делегатов в `Scope`/Singleton — по одному экземпляру на инстанс. [доки introduction]
- Непрозрачным окнам оставлять непрозрачный `color` — Quickshell выберет opaque surface (дешевле по GPU). Динамически меняете прозрачность → `surfaceFormat.opaque: false`. [доки FAQ]
- Скруглённые окна: `color: "transparent"` + внутренний `Rectangle { radius }`. **QTBUG-137166:** у прозрачного Rectangle не трогайте `border` (дырка в окне); воркараунд — `border.width: 0`. [доки FAQ]
- Блокирующие операции (`FileView.blockLoading`, `blockWrites`) — только для жизненно важных конфигов до открытия окон. [доки]
- Долгоживущие потоки — `SplitParser`, разовые выводы — `StdioCollector`. [доки FAQ]
- `layer.enabled: true` + `ShaderEffectSource` для кэширования статичной сложной графики (сам `ClippingRectangle` из Quickshell.Widgets так устроен). Blur — `MultiEffect.blurEnabled` и т.п.; тяжёлый blur — дорогой, кэшируйте и не блурьте анимированное без нужды. [вывод + устройство ClippingRectangle.qml]
- Демон: `qs -c <name> -n -d`; автоперезапуск после краша встроен (crash handler, отключается `QS_DISABLE_CRASH_HANDLER`). [доки advanced + CLI]
- Маска ввода (`mask: Region`) должна повторять видимую форму (скругления), чтобы клики «мимо» уходили в окна/композитор. [вывод, Region доки]
- `updatesEnabled: false` для скрытых тяжёлых окон (OSD и т.п.). [qmltypes — свойство существует; рекомендация — вывод]

---

## 8. Графика

Всё стандартное `import QtQuick` (Qt 6.12) доступно, включая:

- **Rectangle**: `color`, `radius` и **покоординатные радиусы** (`topLeftRadius` и т.д., Qt 6.7+), `border { color; width; pixelAligned }`, `gradient`. Градиенты: `gradient: Gradient { orientation: Gradient.Vertical; GradientStop {...} }`; отдельный тип `LinearGradient` живёт в **`import QtQuick.Shapes`** (ShapePath) — для произвольных фигур вместе с `Shape`, `ShapePath`, `Glyphs`? — нет: глифы — это `QtQuick.Shapes`' `ShapePath`+`Text`; прямого `Glyphs` типа в QtQuick.Shapes нет (есть `Shape`, `ShapePath`, путь-команды). **[поправка: `Glyphs` в QtQuick.Shapes отсутствует; текст рендерится `Text`/`TextEdit`. Уверенность: qmltypes Qt не проверял построчно — вывод]**
- **ShaderEffect** (`import QtQuick`): GLSL пишется на **Qt Scene Graph shader-языке** (in/out, `varying` в старом стиле), шейдеры подгружаются из заранее скомпилированных `.qsb` файлов (`fragmentShader: "qrc:/.../cliprect.frag.qsb"` — так делает сам Quickshell в ClippingRectangle). Uniform-ы — обычные QML-свойства (`property color backgroundColor; property ShaderEffectSource content`), плюс стандартные `vertexShader/fragmentShader/blending/mesh/meshResolution`. Компиляция: `qsb` из Qt (qt6-shadertools) `.vert/.frag → .qsb`. [qmltypes ClippingRectangle.qml — подтверждено на практике]
- **ShaderEffectSource** (`sourceItem`, `hideSource`, `live`, `recursive`, `textureSize`, `format`, `mipmap`, `smooth`) и `Item.layer.enabled/layer.effect/layer.smooth/layer.textureSize` — кэширование в текстуру. [стандарт Qt; используется в ClippingRectangle]
- **MultiEffect — ДОСТУПЕН**: `import QtQuick.Effects` установлен в системе (Qt 6.12, плагин `/usr/lib/qt6/qml/QtQuick/Effects`), экспортирует **`MultiEffect 6.5+`** и **`RectangularShadow 6.9+`** (внутренний `BlurItem`). Свойства MultiEffect: `source`, `autoPaddingEnabled/paddingRect`, `shadowEnabled`, `shadowBlur`, `shadowHorizontalOffset/VerticalOffset`, `shadowColor`, `shadowScale`, `blurEnabled`, `blur`, `blurMax`, `blurMultiplier`, `saturation`, `brightness`, `contrast`, `colorization`, `maskEnabled` и т.д. Доки Quickshell прямо советуют: прямоугольные тени — `RectangularShadow`, тени прочих форм — `MultiEffect.shadowEnabled`. [проверено по plugins.qmltypes Qt 6.12 на машине + доки FAQ]
- **OpacityMask** — из **`import Qt5Compat.GraphicalEffects`** (пакет qt6-5compat 6.12.0 **установлен**), альтернатива на MultiEffect: `MultiEffect { maskEnabled: true; maskSource: ... }`. [вывод по установленным пакетам]
- **Canvas** (`import QtQuick`) — 2D-контекст, доступен; тяжёлый, для статики кэшировать. [стандарт Qt]
- Quickshell-специфичное:
  - `Quickshell.Widgets` (`import Quickshell.Widgets`): `IconImage { source; asynchronous; mipmap; status; implicitSize; actualSize (ro); backer : Image }` — иконки 1:1; `ClippingRectangle { contentUnderBorder; contentInsideBorder; border : clippingRectangleBorder {color; width; pixelAligned}; radius + покомпонентные; color; antialiasing }` — Rectangle с клиппингом по скруглённой рамке (реализован через ShaderEffect); `ClippingWrapperRectangle { radius; ... }` — обёртка-маргин для скругления картинок (рекомендация доков FAQ); `WrapperRectangle`, `WrapperItem`, `WrapperMouseArea`, `MarginWrapperManager` (margin/extraMargin/resizeChild). [qmltypes + QML-исходники пакета]
  - `Region` для масок ввода (см. §4).
- Прозрачность окна: `PanelWindow.color: "transparent"` + `surfaceFormat.opaque: false` при необходимости.

---

## 9. Текст

Всё стандартное QtQuick:

- **Text**: `text`, `font.family` (кастомный TTF — через **`FontLoader { id: f; source: Qt.resolvedUrl("fonts/Inter.ttf") }`**, затем `font.family: f.name`), `font.pixelSize`, `font.weight`, `font.letterSpacing`, `color`, `elide`, `wrapMode`, `maximumLineCount`, `textFormat: Text.PlainText | StyledText | AutoText` (по умолчанию разметка рендерится — см. замечание NotificationServer про markup), `renderType: Text.QtRendering | Text.NativeRendering` (глобально — прагма `NativeTextRendering`). [стандарт Qt + доки]
- **TextInput** (голый ввод) / **TextField** (`import QtQuick.Controls` — стиль по умолчанию Fusion, см. `RespectSystemStyle`): `text`, `echoMode`, `placeholderText`, `cursorDelegate` (свой делегат курсора — стандартное свойство TextInput/TextEdit), `font`, `color`, `onAccepted`. [стандарт Qt;Controls стиль — доки advanced]
- **TextMetrics** (`import QtQuick`): `font`, `text`, и метрики `width/advanceWidth/boundingRect/height/xHeight/...` — для моноширинных метрик (ширина символа: `TextMetrics { font.family: "monospace"; text: "0" }` → `.advanceWidth`; плюс `font.letterSpacing`/`font.pixelSize` множители `0.6`). [стандарт Qt]
- Внимание к шрифтам: прагма `DropExpensiveFonts` исключает woff/woff2 (загрузка шрифтов в Qt дорогая). [доки advanced]

---

## 10. Модели и task manager / список окон

- **Repeater** (QtQuick) — короткие списки (трей, плееры) + RowLayout/ColumnLayout. [доки FAQ]
- **ListView / GridView** (QtQuick) — длинные/скроллимые (ленчер). [доки FAQ]
- **ListModel + ListElement** (QtQuick) — изменяемая своя модель (`append/set/clear`) — поддерживается, это чистый Qt.
- **ScriptModel** (Quickshell) — модель из JS-массива/вычисляемого списка; предпочтительнее ListModel для функциональных стилей (`values: screens.map(...)`), `objectProp` для identity, `comparisonMode: ObjectComparison.Identity|Structure` минимизирует ре-рендеры. [qmltypes]
- **ObjectModel** (Quickshell) — read-only обёртка над списками QObject от Quickshell (`Hyprland.toplevels`, `NotificationServer.trackedNotifications`, `DesktopEntries.applications`, `SystemTray.items`, `QsMenuOpener.children` — везде тип `UntypedObjectModel`). Использовать прямо как `model:` у Repeater/ListView. [qmltypes]
- **ObjectRepeater** — в 0.3.2 **отсутствует** (появился позже); использовать Repeater + ObjectModel. [сайдбар доков v0.3.2 vs git]

### Список окон для таскбара
Два источника:

1. **Hyprland IPC** (`import Quickshell.Hyprland`) — richest: `Hyprland.toplevels` (ObjectModel из `HyprlandToplevel`: `address, title, activated, urgent, workspace, monitor`), обновляется автоматически из event-сокета. Фильтрация по `workspace.id == Hyprland.focusedWorkspace.id` для «окон текущего воркспейса». Фокус окна: `Hyprland.dispatch("focuswindow address:" + tl.address)`. Закрытие: `Hyprland.dispatch("closethewindow address:...")` (актуальное имя диспетчера `closewindow` в новых Hyprland — проверить `hyprctl dispatch list`). [qmltypes + вывод по dispatch]
2. **Wayland-независимо** (`import Quickshell.Wayland`): `ToplevelManager` (синглтон, ext-foreign-toplevel/wlr-тoplevel-management): `toplevels : ObjectModel<Toplevel>`, `activeToplevel : Toplevel`. `Toplevel`: `appId : string, title : string, parent : Toplevel, activated : bool, screens : list<ShellScreen>, maximized/minimized/fullscreen : bool (writable!)`, методы `activate()`, `close()`, `fullscreenOn(screen)`, `setRectangle(window, rect)`, сигнал `closed()`. Минус против Hyprland: нет workspace/urgent. [qmltypes]

Класс приложения для иконок: `Toplevel.appId` / desktop-entry matching через `DesktopEntries.heuristicLookup(appId).icon` или `Quickshell.iconPath(...)`. [qmltypes + вывод]

### Процессы
Списка процессов в Quickshell нет — читайте `/proc` через `FileView { watchChanges: false }` или внешний `Process` (`ps`, `pgrep`). [вывод]

---

## 11. Прочее полезное (мелочи)

- `Quickshell.I3` — аналог Hyprland-модуля для i3 (`I3`, `I3Event`, `I3Monitor`, `I3Workspace`); в 0.3.2 нет `I3IpcListener` (это уже newer). Не нужен для Hyprland. [qmltypes]
- `Quickshell.Services.Mpris` (`Mpris.players`, `MprisPlayer { trackTitle, trackArtUrl, playbackState, loopState, position, ... }`) — медиаплеер для панели. [qmltypes]
- `Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink`, `PwObjectTracker`, `PwNodeAudio.volume/audioChannels`) — громкость/микшер без вызова wpctl. [qmltypes]
- `Quickshell.Services.SystemTray` — трей (см. §4). `Quickshell.Services.UPower` — батарея. `Quickshell.Services.Greetd`, `Pam` (PamContext — проверка пароля), `Polkit` — лок-скрин/агент. `Quickshell.Bluetooth`, `Quickshell.Networking` (NetworkManager) — присутствуют в 0.3.2. [qmltypes пакета]
- `Quickshell.Wayland` дополнительно: `WlSessionLock`/`WlSessionLockSurface` (экран блокировки), `ScreencopyView` (захват экрана в Item), `IdleInhibitor`/`IdleMonitor`/`ShortcutInhibitor`, `BackgroundEffect` (блюр фона слоя — требует поддержки композитором; у Hyprland 0.57 — свои рецепты блюра, использовать осторожно). [qmltypes + сайдбар v0.3.2; состояние Idle*-типов в 0.3.2 подтверждено наличием папок `_IdleInhibitor/_IdleNotify/_ShortcutsInhibitor`]
- Примеры конфигов: https://github.com/quickshell-mirror/quickshell-examples (activate_linux, focus_following_panel, lockscreen, mixer, reload-popup, volume-osd, wlogout). [GitHub API]

---

## 12. Краткая шпаргалка импортов

```qml
import Quickshell                          // PanelWindow, FloatingWindow, PopupWindow, Quickshell, Variants, Scope,
                                           // Singleton, ShellRoot, SystemClock, ScriptModel, LazyLoader, Region,
                                           // DesktopEntries, IconImage нет — см. Widgets, EasingCurve, ColorQuantizer...
import Quickshell.Io                       // Process, StdioCollector, SplitParser, FileView, JsonAdapter,
                                           // Socket, SocketServer, IpcHandler
import Quickshell.Wayland                  // WlrLayershell, WlrLayer, WlrKeyboardFocus, Toplevel, ToplevelManager,
                                           // WlSessionLock, ScreencopyView, IdleInhibitor...
import Quickshell.Hyprland                 // Hyprland, HyprlandMonitor/Workspace/Toplevel, GlobalShortcut,
                                           // HyprlandFocusGrab, HyprlandWindow
import Quickshell.Services.Notifications   // NotificationServer, Notification, NotificationAction, ...
import Quickshell.Services.SystemTray      // SystemTray, SystemTrayItem
import Quickshell.Services.Mpris           // Mpris, MprisPlayer
import Quickshell.Services.Pipewire        // Pipewire, PwObjectTracker, ...
import Quickshell.Widgets                  // IconImage, ClippingRectangle, ClippingWrapperRectangle, WrapperRectangle...
import QtQuick                             // Rectangle, Text, Image, Timer, Repeater, ListView, Loader, ShaderEffect,
                                           // ShaderEffectSource, TextMetrics, FontLoader, Canvas...
import QtQuick.Controls                    // TextField, Button, ScrollView (стиль Fusion по умолчанию)
import QtQuick.Layouts                     // RowLayout, ColumnLayout...
import QtQuick.Effects                     // MultiEffect, RectangularShadow  (подтверждено: установлен Qt 6.12)
import QtQuick.Shapes                      // Shape, ShapePath, LinearGradient (внутри ShapePath)
import Qt5Compat.GraphicalEffects          // OpacityMask (пакет qt6-5compat установлен)
```
