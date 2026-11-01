# pi как бекенд чат-агента для desktop-панели (Quickshell/QML)

Исследование локальной установки pi 1.4.0 + документация + рекомендации по интеграции.
Дата: 2026-11-01.

---

## ЧАСТЬ 1. Локальная установка

### 1.1. Что это

- `~/.pi/agent/bin/pi` — шелл-обёртка: резолвит симлинки, читает `~/.pi/agent/install/current-version`
  и запускает `~/.pi/agent/install/releases/<ver>/node_modules/.bin/pi` (Node.js из
  `~/.local/share/pi-node/current/bin`). Т.е. это **npm-пакет**, не монолитный бинарь.
- Установленная версия: **1.4.0**, пакет `@earendil-works/pi-coding-agent` (scope сменился
  с `@mariozechner/*`; репозиторий — `badlogic/pi-mono`, сейчас живёт как `earendil-works/pi`).
  Скоуп в `node_modules`: `pi-agent-core`, `pi-ai`, `pi-coding-agent`, `pi-codemode`,
  `pi-mcp`, `pi-telemetry`, `pi-tui`.
- **Полная документация лежит локально** (версия-точная, лучше GitHub):
  `~/.pi/agent/install/releases/1.4.0/node_modules/@earendil-works/pi-coding-agent/docs/`
  — `rpc.md`, `rpc-commands.md`, `rpc-extension-ui.md`, `json.md`, `sdk.md`, `extensions.md`,
  `session-format.md`, `cli-integration.md`, `settings.md`, `packages.md`, `mcp.md` и др.
  Примеры: `.../examples/rpc-client.ts`, `.../examples/sdk/*.ts`, `.../examples/extensions/*.ts`.

### 1.2. CLI: подкоманды и режимы

```
pi --version          # 1.4.0
pi --mode rpc         # долгоживущий процесс: JSONL-команды на stdin, события+ответы на stdout
pi --mode json "..."  # один прогон, JSONL-события на stdout, выход
pi -p "..."           # print-режим: только финальный текст
pi                    # интерактивный TUI
```

**Отдельных подкоманд `rpc` / `serve` / `a2a` нет.** RPC — это не подкоманда, а **`--mode rpc`**.
Сервера/сокетов из коробки нет: только stdio-протокол. Остальные подкоманды: `install/remove/
uninstall/update/list/config/auth/mcp`, `--export file.html`, `--list-models`.

Ключевые флаги для интеграции: `--session-dir`, `--session <path|id>`, `--continue/-c`,
`--resume/-r`, `--fork`, `--session-id <id>`, `--no-session`, `--name/-n`, `--model`,
`--provider`, `--thinking`, `--tools/-t`, `--exclude-tools/-xt`, `--no-tools/-nt`,
`--extension/-e`, `--no-extensions`, `--no-mcp`, `--system-prompt`, `--append-system-prompt`.

### 1.3. Конфигурация

| Файл | Содержимое |
|---|---|
| `~/.pi/agent/settings.json` | `defaultProvider: "eliza"`, `defaultModel: "glm-5-3"`; пакеты: `npm:pi-subagents`, `npm:pi-goal-x`; блок `subagents` (defaultModel + agentOverrides для scout/worker/delegate/reviewer/oracle/advisor/researcher) |
| `~/.pi/agent/models.json` | кастомный провайдер **eliza** (Yandex internal), `api: "openai-completions"`, baseUrl `https://api.eliza.yandex.net/raw/internal/<model>/v1`; модели: deepseek-v4-flash, deepseek-v4-flash-batch (1M ctx), glm-5-3, gpt-oss-120b, qwen3-8-* (часть с image-входом). Внимание: `apiKey` лежит в models.json в открытом виде |
| `~/.pi/agent/mcp.json` | HTTP-сервер `yandex-gitgut` (`http://localhost:8888/mcp`: Трекер, supchat, Bilim, wiki, staff, Magic) + `playwright` (stdio, firefox) |
| `~/.pi/agent/auth.json` | ключи провайдеров (mode 600) |

### 1.4. `~/.pi/agent/pi-subagents/` — что это

**Не исходники.** Папка-маркер установленного расширения: внутри только
`last-seen-version.json`. Сам пакет — в `~/.pi/agent/npm/node_modules/pi-subagents/`
(версия 0.79.1, автор Nico Bailon, `pi install npm:pi-subagents`). Это расширение
«single-agent delegation and scripted multi-agent workflows»: инструмент `subagent`,
встроенные агенты scout/worker/reviewer/oracle/delegate/researcher/..., фоновые прогоны
(«Fleet»), сохранённые workflows, `/council`, missions.

### 1.5. Кастомные агенты: `~/.pi/agent/agents/*.md`

Формат (поддерживается pi-subagents): YAML frontmatter + системный промпт.

```markdown
---
name: ths-reviewer
description: Ревьюер багрепортов Яндекс 360...
advertise: false        # true = попадает в каталог advertised_subagents в системном промпте родителя
tools: read, bash, contact_supervisor, mcp:yandex-gitgut
model: glm-5-3          # опционально; также thinking, timeoutMs, cwd и др.
timeoutMs: 600000
---
Ты — ревьюер процесса багрепортов...
```

Сейчас есть `ths-reviewer.md` (advertise: false) и `image-maker.md` (advertise: true).
Программно (RPC/SDK) сабагент запускается инструментом `subagent` из промпта:
`subagent({agent:"reviewer", task:"..."})`, `{workflow:"parallel", args:{tasks:[...]}}`,
`{action:"status"|"stop"|"resume", id, options:{...}}` — либо можно самому держать отдельный
RPC-процесс на агента: `pi --mode rpc -e <extension> -t read,bash ...`.

### 1.6. `~/.pi/agent/missions/` — артефакты pi-subagents/goal

`missions/index/*.json` — индекс миссий: `{schemaVersion, missionId, projectRoot,
recordPath, title, status: "completed"|..., updatedAt, lastRunId}`; тела — в
`missions/projects/<hash>/<missionId>.json`. Это персистентные цели/задачи расширения
goal/missions, а не формат сессий чата.

### 1.7. Формат файлов сессий (`~/.pi/agent/sessions/`)

- Группировка по cwd: `sessions/--home-gitgut--/`, `sessions/--home-gitgut-Проекты-eliza__/` и т.п.
- Имя файла: `<ISO-время>_<uuid>.jsonl`.
- Формат: **append-only JSONL, дерево записей** (`version: 3`). Первая строка — заголовок:

```json
{"type":"session","version":3,"id":"01a18eca-...","timestamp":"...","cwd":"/home/gitgut"}
```

Типы записей (docs/session-format.md): `session`, `model_change`
(`{provider, modelId}`), `thinking_level_change`, `message` (основной:
`{id, parentId, timestamp, message:{role: system|user|assistant, content: [блоки],
usage, stopReason, provider, model, durationMs, errorMessage}}`),
`usage`, `compaction`, `context_edit`, `branch_summary`, `custom`,
`custom_message`, `label`, `session_info`. Каждая запись ссылается на `parentId`
→ ветвление/fork без удаления истории.

Артефакты сабагентов: `sessions/<dir>/subagent-artifacts/`, плюс у каждого фонового
прогона свой каталог с `events.jsonl` (lifecycle: `subagent.run.started`,
`subagent.step.completed`, `subagent.run.completed`, детские Pi JSON-события) и
`output-<i>.log`; итог — `<runId>.json` в results-каталоге.

---

## ЧАСТЬ 2. Программное управление: RPC, SDK, события, расширения

### 2.1. RPC mode — основной контракт

Запуск: `pi --mode rpc [--no-session] [--cwd ...] [--model ...]`.
**Не JSON-RPC 2.0** — собственный JSONL-протокол, 4 семейства записей:

| Направление | Запись | Назначение |
|---|---|---|
| → stdin | `command` | `{"id":"req-1","type":"prompt","message":"..."}` |
| ← stdout | `response` | `{"id":"req-1","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}` |
| ← stdout | session events | `agent_start`, `message_update`, `agent_settled`, ... |
| оба | extension UI records | диалоги расширений (confirm/select/input/notify/setWidget) |

Фрейминг: **строго JSONL, разделитель только LF** (не `readline` в Node — он режет ещё
по U+2028/U+2029, которые валидны внутри JSON-строк; QML/JS-код тоже читайте по `\n`
из байтового потока). Диагностика — в stderr, stdout только для протокола. Читать stdout
непрерывно (backpressure может застопорить процесс).

Жизненный цикл прогона: ответ на `prompt` = «принято» (`data.disposition` =
`started|queued|handled`), НЕ «готово». Конец работы = событие **`agent_settled`**
(`agent_end` недостаточно — после него бывают ретраи/компакция/очередь).

Основные команды (docs/rpc-commands.md, все с опциональным `id`):

- Промпты: `prompt` (+`images[]` base64, +`streamingBehavior:"steer"|"followUp"`),
  `steer`, `follow_up`, `abort`, `clear_queue`
- Состояние: `get_state` (model, isStreaming, sessionFile, sessionId, messageCount...),
  `get_messages`, `get_last_assistant_text`, `get_entries {since: cursorId}`,
  `get_tree`, `get_session_stats` (токены/стоимость/`contextUsage.percent`),
  `get_commands` (extension-команды, шаблоны, скиллы)
- Модель: `set_model {provider, modelId}`, `cycle_model`, `get_available_models`,
  `set_thinking_level {level}`, `cycle_thinking_level`, `get_available_thinking_levels`
- Очереди: `set_steering_mode`, `set_follow_up_mode`
- Контекст: `compact {customInstructions?}`, `set_auto_compaction`, `set_auto_retry`, `abort_retry`
- Shell: `bash {command}` (стримит `bash_execution_update {id, delta}`), `abort_bash`
- Сессии: `new_session {parentSession?}`, `switch_session {sessionPath}`, `fork {entryId}`,
  `clone`, `get_fork_messages`, `set_session_name {name}`, `export_html {outputPath?}`

### 2.2. События (docs/json.md) — что стримится

```
agent_start → turn_start → message_start(user) → message_end(user)
  → message_start(assistant) → message_update* → message_end(assistant)
  → tool_execution_start → tool_execution_update* → tool_execution_end
  → turn_end → ... → agent_end → agent_settled
```

Стриминг текста — `message_update` с `assistantMessageEvent`:
`text_delta {contentIndex, delta}`, `text_end {content, ...}`, `thinking_delta`,
`toolcall_start/delta/end`, `done`, `error`. Дельты — только приращения; авторитетный
текст — `text_end` / `message_end.message`. Плюс: `queue_update`, `entry_appended`,
`session_info_changed`, `thinking_level_changed`, `compaction_start/end`,
`auto_retry_start/end`, `extension_error`.

**Следствие для UI: стриминг токенов «из коробки» — не нужно ничего дописывать.**

Extension UI через RPC (docs/rpc-extension-ui.md): Pi может запросить у клиента
`select`, `confirm`, `input`, `editor`, и прислать `notify`, `setStatus`, `setWidget`,
`set_title`, `set_editor_text`; клиент отвечает `extension_ui_response`. Это готовый
механизм, чтобы рисовать диалоги подтверждения pi прямо в QML-панели (TUI-компоненты
расширений при этом недоступны — только эти записи).

### 2.3. SDK (in-process, Node/Bun)

`@earendil-works/pi-coding-agent` экспортирует `createAgentSession()`, `SessionManager`,
`AgentSessionRuntime`, тип `JsonAgentSessionEvent` и **`RpcClient`** (подпроцессный
клиент: сам стартует pi, коррелирует id, типизированные методы, слушатели событий,
`promptAndWait()`, `waitForIdle()`).

```typescript
import { createAgentSession } from "@earendil-works/pi-coding-agent";
const { session } = await createAgentSession({ sessionManager: SessionManager.inMemory() });
const off = session.subscribe((e) => {
  if (e.type === "message_update" && e.assistantMessageEvent.type === "text_delta")
    process.stdout.write(e.assistantMessageEvent.delta);
});
await session.prompt("Привет");          // steers/followUp: session.steer()/session.followUp()
console.log(session.getLastAssistantText());
off(); session.dispose();
```

SDK даёт полный контроль (модели, tools, resourceLoader, extensions, settings), но
тянет Node-рантайм в хост-процесс.

### 2.4. Расширения (TypeScript) и хуки

Расширение — TS-модуль с default-фабрикой `export default function (pi: ExtensionAPI)`.
Загрузка: `pi --extension ./hello.ts`, каталоги `~/.pi/agent/extensions/` (user) и
`.pi/agent/extensions/` (project), либо пакет `npm:...` в `settings.packages` (как
pi-subagents). `jiti` компилирует TS на лету — без сборки.

Главные API: `pi.on(event, handler)` — хуки; `pi.registerTool()` (TypeBox-схема,
`execute()`, exposure: direct/model-only/codemode/deferred/hidden); `pi.registerCommand()`;
`pi.registerFlag()`; `pi.sendUserMessage()/sendMessage()`; `pi.appendEntry()`
(персист вне контекста модели); `pi.registerProvider()/registerMcpServer()/
registerVirtualModel()`; `pi.events` (коммуникация между расширениями, in-process only).

События/хуки (полный список в docs/extensions.md):

| Группа | События |
|---|---|
| Ввод | `input` (можно перехватить/трансформировать/съесть), `before_agent_start` (промпт-секции, tools, system prompt) |
| Прогон | `agent_start`, `agent_end`, `agent_before_settle` (можно continuation), `agent_settled` |
| Тёрн | `turn_start`, `turn_end`, `context`, `context_with_system` (фильтрация транскрипта) |
| Провайдер | `before_provider_headers`, `before_provider_request`, `after_provider_response`, `provider_stream_event` |
| Сообщения | `message_start`, `message_update`, `message_end` (можно заменить финальное сообщение) |
| Инструменты | `tool_execution_start`, `tool_call` (можно block/ mutate → permission-gate), `tool_execution_update`, `tool_result` (redact), `tool_execution_end` |
| Сессия | `session_start`, `session_before_switch`, `session_before_fork`, `session_shutdown`, `project_trust`, `resources_discover`, `mcp_servers_change` |

Пример permission-gate (из docs):

```typescript
pi.on("tool_call", async (event, ctx) => {
  if (event.toolName === "bash" && /rm -rf/.test(event.input.command))
    return { block: true, reason: "destructive command blocked" };
});
```

Для UI-интеграции расширение — способ: (а) поставить хуки-уведомления и дублировать
события в сокет/файл для панели, (б) блокировать/разрешать tool-вызовы по решению UI.

### 2.5. Сабагенты (pi-subagents) — как наблюдать из UI

- Единственный канал запуска — инструмент `subagent` в родительской сессии
  (`{agent, task}`, `{workflow:"parallel",...}`, `async:true`, management-`action`).
  Прямого внешнего API «spawn сабагента» нет: дергается через `prompt`.
- Foreground-дети стримятся в родительскую транскрипт (обычные `tool_execution_*`
  события инструмента `subagent` видны в RPC как у любого инструмента).
- Background-дети пишут **файловые артефакты**: `events.jsonl` (lifecycle + детские
  события, `message_update` выброшен), `output-<i>.log`, `status.json`, итог
  `<runId>.json`; каталог виден в `details.asyncDir` тул-результата. `pi.events`
  **не** работает между процессами — для кросс-процессной координации только файлы
  или pi-intercom.
- В RPC-режиме всё это наблюдаемо: события инструмента `subagent` в стриме +
  чтение `events.jsonl` для «флота».

---

## ЧАСТЬ 3. Варианты архитектуры бекенда

### Вариант A. `pi --mode rpc` подпроцесс на сессию, JSONL over stdio (рекомендую)

**Схема:** Quickshell/QML панель держит `Process { command: ["pi","--mode","rpc", ...] }`
на каждую сессию чата (или один глобальный + переключение `switch_session`).
QML/JS-класс-обёртка: пишет JSON+`\n` в stdin, читает stdout по LF, маршрутизирует
`response` по `id`, события — в `ListModel` чата.

```
QML Panel ──stdin(JSONL)──► pi --mode rpc ──stdout(JSONL)──► QML
                             │  (response по id, events: text_delta, tool_*, agent_settled)
                             └── свои extensions при необходимости (-e ...)
```

- **Стриминг**: нативно, `message_update.assistantMessageEvent.text_delta` → append в
  delegate чата. Конец — `agent_settled`.
- **История**: либо `--no-session` + `get_messages`/`get_entries {since}` в памяти UI,
  либо полноценные файлы сессий + `--continue`/`--session`/`switch_session` — тогда
  история переживает рестарт панели и видна в TUI-pi (общий формат!).
- **Сабагенты/хуки**: сабагенты через `subagent`-инструмент в промпте (события видны
  в стриме), фоновые — чтение `events.jsonl`. Хуки — любое расширение, подключённое
  `-e`, плюс RPC extension UI (confirm/select/input) прямо в панель.
- **Плюсы**: минимум движущихся частей; нет Node-кода у вас; изоляция (падение pi не
  валит панель); все фичи CLI (модели, MCP, скиллы, расширения) сразу; официальная
  версия-точная документация; стриминг и steer/follow_up из коробки.
- **Минусы**: JSONL-парсинг в QML/JS (прост, но осторожно с LF-framing и U+2028);
  по процессу на сессию (для 1–5 чатов — норм); нет общего снапшота «флота» сабагентов —
  надо читать артефакты.
- **Сложность**: низкая–средняя. MVP — пара сотен строк QML/JS.

Мини-скетч QML-стороны:

```qml
Process {
    id: pi
    command: ["pi", "--mode", "rpc", "--no-session",
              "--model", "eliza/glm-5-3", "--session-dir", sessionDir]
    stdout: SplitParser { onReady: chatBackend.onRecord(line) }  // посимвольно по \n
}
// chatBackend.onRecord(JSON.parse(line)):
//   type==="response"  → resolve pending promise по record.id
//   type==="message_update" && assistantMessageEvent.type==="text_delta" → append(delta)
//   type==="agent_settled"   → разблокировать input
// отправка: pi.write(JSON.stringify({id:"req-"+(++n), type:"prompt", message: text}) + "\n")
```

### Вариант B. Node-бридж на SDK/RpcClient + WebSocket/unix socket к QML

**Схема:** маленький Node-демон (`@earendil-works/pi-coding-agent`): либо `RpcClient`
(N подпроцессов pi), либо `createAgentSession()` in-process; наружу — WebSocket
(`ws`) или unix socket; QML WebSocketPanel подключается.

- **Стриминг**: `session.subscribe()` / `rpcClient.on(event)` → пересылка в WS.
- **История**: `SessionManager` (persistent или inMemory), `AgentSessionRuntime`
  (newSession/switchSession/fork), полный контроль ресурсоloading.
- **Сабагенты/хуки**: расширения можно регистрировать inline-фабриками
  (`extensionFactories`), читать артефакты, агрегировать флот, делать свои JSON-API
  поверх (`get_commands`, статистика и т.д.).
- **Плюсы**: типизированный клиент (`RpcClient`), полный контроль, один демон на
  много сессий, легко добавить свою business-логику (роутинг агентов, БД, поиск).
- **Минусы**: +1 компонент (Node-сервис, его деплой/автостарт/健康-check), дублирование
  протокола (WS-схема своя), сложность отладки выше.
- **Сложность**: средняя–высокая. Оправдан, если панель мульти-сессионная, нужен
  центральный сервис для нескольких UI или сложная логика поверх.

### Вариант C. Headless `pi -p` / `pi --mode json` + парсинг JSONL сессий

**Схема:** на каждое сообщение — `pi -p -c "..."` (continue) или `pi --mode json`;
историю UI читает прямо из `sessions/**/*.jsonl`.

- **Стриминг**: `--mode json` даёт события, но процесс одноразовый — на каждое
  сообщение холодный старт (MCP-серверы, расширения, discovery = секунды), очередь
  сообщений UI не строится, steer/follow_up недоступны.
- **История**: только чтение файлов; параллельные записи из двух клиентов (панель +
  TUI) рискуют рассинхронизироваться.
- **Сабагенты/хуки**: работают внутри прогона, но наблюдать интерактивно нельзя.
- **Плюсы**: тривиально.
- **Минусы**: нет настоящего чата; медленно; нет управления; гонки при параллельном
  доступе. **Не рекомендую** для панели с быстрым откликом (годится лишь для
  «кнопочных» one-shot действий вроде «сгенерируй картинку»).

### Рекомендация

**Вариант A** — для desktop-панели Quickshell с быстрым откликом:
это официально поддерживаемый режим ровно для вашего случая («IDEs and custom user
interfaces», docs/rpc.md), стриминг/steer/follow_up/extension-диалоги/файловые сессии
из коробки, нулевая инфраструктура. Начать с `--no-session` в памяти, затем включить
`--session-dir`, чтобы история была общей с TUI-pi. **Вариант B** подключать позже,
только если появится потребность в центральном мульти-сессионном сервисе.
**Вариант C** держать как утилитарный путь для one-shot команд.

Практические советы для реализации:
1. Читать stdout байтово и резать строго по `\n` (не `String.split('\n')` по декодированной
   строке с потерей частичных строк; в QML — аккумулировать буфер, искать `\n`).
2. Подписываться на события **до** отправки `prompt` (гонка с быстрым завершением).
3. Ждать `agent_settled`, не `agent_end`.
4. Всегда передавать `id` в командах и коррелировать `response`.
5. Esc-поведение UI: `clear_queue` → `abort`, вернуть текст из ответа в редактор.
6. Для подтверждений опасных действий — расширение permission-gate + RPC extension UI
   (`confirm`), иначе pi по умолчанию исполняет bash без вопросов.
7. Прогресс/статистика: `get_session_stats` (`contextUsage.percent` — индикатор контекста),
   `compact` поthreshold.

---

## ЧАСТЬ 4. Открытые вопросы

1. **Одна сессия или мульти-чат?** Определяет: процесс на чат (A) или Node-бридж (B).
2. **Общая история с TUI-pi?** Если да — включать `--session-dir ~/.pi/agent/sessions`
   (по умолчанию так) и не использовать `--no-session`; учесть, что одновременная запись
   в одну сессию из панели и TUI нежелательна.
3. **Права инструментов**: панель — это «всегда разрешено» (сейчас pi исполняет bash
   без подтверждений), или нужен confirm-диалог в UI (расширение permission-gate)?
4. **Модель по умолчанию для чата**: `eliza/glm-5-3` (сейчас default, maxTokens 16384),
   `deepseek-v4-flash-batch` (1M контекст) или выбор в UI через `get_available_models`?
5. **Нужен ли в панели мониторинг сабагентов-«флота»** (чтение `events.jsonl` из
   `subagent-artifacts`) или достаточно отображения foreground-вызовов `subagent` в чате?
6. **Аутентификация eliza**: `apiKey` в `models.json` лежит в открытом виде — оки ли это
   для машины, или вынести в `auth.json`/env?
