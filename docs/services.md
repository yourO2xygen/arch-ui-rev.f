# Сервисы (синглтоны)

Все синглтоны — `pragma Singleton` + запись в services/qmldir. Сервисы не
импортируют UI. Два общих урока, действующих для всех:

- Процесс перед стартом проверяется FileView-пробой бинаря: QS `Process` при
  FailedToStart **не эмитит** `exited` — без пробы получаешь молча мёртвый
  процесс и гадание.
- Мутации массивов-моделей — in-place + один `slice()` за кадр через
  `Qt.callLater(_flush)` (иначе полный rebuild делегатов на каждый тик).

## SysMon — всегда активен

Что читает: `/proc/stat` (cpu — дельта между тиками, Timer 2s),
`/proc/meminfo`, `/proc/uptime`, `/proc/loadavg`, `/proc/sys/kernel/*`,
`/sys/class/power_supply/BAT*`, `/sys/class/net` + `ip -brief addr` раз в 30s.
GPU/VRAM — ветка по вендору, выбор один раз при старте:
nvidia → один долгоживущий `/usr/bin/nvidia-smi … -l 5` (Process + SplitParser);
нет бинаря → скан `/sys/class/drm/card[0-9]/device/vendor` (карты могут нумероваться
не с card0): `0x1002` → **amdgpu** sysfs (`gpu_busy_percent`,
`mem_info_vram_used/total`, `hwmon/hwmonX/temp1_input` — FileView `watchChanges`,
без Process; temp-файла может не быть → gpuTemp 0); `0x8086` → **intel**
name-only (`gpuInfo "name-only"`: gpuName в caption вместо ghost, % / VRAM — dim,
у i915 метрик в sysfs нет); ничего → ghost-значения «—» и пустые полосы, как
раньше. На этой машине nvidia-smi **нет**, карта — intel i915 ⇒ name-only; probes
скана молчат (`printErrors: false`). Процессы SysMon гасятся в
`Component.onDestruction`, чтобы перезагрузка конфига не плодила nvidia-smi.

## ProcMon — только при видимости TaskMgr

`/usr/bin/ps -eo pid,comm:40,pcpu,rss,user --sort=-pcpu --no-headers` раз в 2s,
**только пока `taskmgr` открыт в слоте A** (иначе поллинг спит). `ps` —
одноразовый на тик (StdioCollector). `kill(pid)` — SIGTERM
(`/usr/bin/kill`): строка уходит фейдом (Motion.killFade) и выпадает из модели,
когда следующий тик ps её не вернул («подтверждение исчезновением»); пережил
SIGTERM — строка возвращается.

## DockerMon — ленивый синглтон, потоки при открытой панели

Ленив **инстанс**: не создаётся, пока никто не читает его свойства (foot-биндинг
в shell.qml в ветке `docker`) — события/логи не живут до первого открытия
панели, это фича.

Держит (при видимости панели): один `docker events --format json` (push) +
`docker ps -a` refresh по событию (дебаунс 350ms), `docker logs --tail 200 -t -f`
на выбранный контейнер (смена контейнера убивает старый Process — утечка
недопустима), `docker stats --no-stream` по требованию (переопрос 5s).

**Права**: если сокет не доступен (юзер не в группе docker) — однократная проба
`sudo -n docker version`, при успехе режим `viaSudo` (`sudo -n docker …`).
Рекомендованный шаг: `sudo usermod -aG docker gitgut` + релогин — тогда фолбэк
вообще не включится (сам он при появлении группы не выключается). Ни то ни се —
ghost-состояние с причиной, повторных попыток нет.

**reap-механика**: жёсткое убиение демона (краш, `pkill -9`) оставляет
`sudo+docker events/logs -f` сиротами навсегда (ppid → systemd --user, сами не
умирают). Стартовый reap находит их по маркеру командной строки
`/usr/bin/docker (logs --tail 200|events --format)`, но kill выполняется только
при **всех** гейтах: uid-совпадение (root при viaSudo / текущий юзер), args
startsWith маркера, regex-парсинг pid/ppid и fd-чек docker.sock через
`ss -xp` (cross-check inode). Отказ любой пробы → skip + warn, ноль kill.

Зависимость от способа запуска: детект своих стримов рассчитан на канонический
запуск `qs -c shell --no-duplicate --daemonize` (см. README) — не меняй форму
запуска, не проверив reap.

## AgentBridge — ленивый процесс, живой объект

Объект-синглтон инстанцируется при старте шелла; **процесс pi** стартует лениво
при первом открытии `chat`/`aimgr` и живёт после ухода с панелей. Детали и
протокол — [agent-chat.md](agent-chat.md).

## NotifStore — всегда активен

Полный notification daemon + стор тостов/истории. Активен всегда (D-Bus-имя
держит шелл). Персист — JSONL `~/.cache/arch-ui/notifications.jsonl`
(TTL 7d, лимит 200, bootId). Детали — [notifications.md](notifications.md).

## LayoutState

Менеджер слотов {A,B,C,bar} → panelId, персист `PersistentProperties`
(reloadableId «layout»). Тумблеры IPC живут здесь же. —
[layout.md](layout.md).

## Диагностика «сервис не работает»

1. `qs log` — warn от имени сервиса (все логи с префиксом `[archui]`/сервиса).
2. Проверь существование бинаря (`/usr/bin/docker`, `/usr/bin/ps`, pi).
3. Права: docker-сокет → см. выше viaSudo/usermod.
4. Менял синглтон? Полный рестарт демона обязателен.
