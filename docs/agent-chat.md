# Агент-чат: мост к pi RPC

Мост — services/AgentBridge.qml; UI — components/AgentChat.qml (слот C) и
components/AgentMgr.qml (слот C). Бекенд — `pi` 1.4.0 в rpc-режиме
(JSONL over stdio).

## Фактическая команда

```
/home/gitgut/.pi/agent/bin/pi --mode rpc --no-session --no-mcp \
  --no-extensions --no-skills --no-prompt-templates --no-themes --no-context-files
```

(при override добавляются `--provider <p> --model <m>`). Абсолютный путь —
обязателен: PATH демона ненадёжен. Перед стартом бинарь проверяется
FileView-пробой: QS `Process` при FailedToStart **не эмитит** `exited` — без
пробы гадание на мёртвом процессе.

Профиль минимальный: без MCP/расширений/скиллов/тем/внешнего контекста.
Сессия — in-memory (rpc список сессий не отдаёт), кнопка **New thread** даёт
чистую ленту.

## ⚠️ Permission-гейта нет

Решение юзера (SPEC Q4): confirm-диалоги не показываются — pi **исполняет
bash и любые инструменты без вопросов**. Extension-запросы pi
(`extension_ui_request`) рисуются карточкой «agent question» в чате, но
инструмент-конфирмы не гейтятся. Помни об этом, просишь агента что-то сделать.

## Протокол (проверено живьём на 1.4.0)

```
→ {"id":"req-N","type":"prompt","message":"…"}          + LF
← {"type":"response","id":"req-N",...,"disposition":"started|queued|handled"}   — приёмка, НЕ готовность
← agent_start → message_update.assistantMessageEvent.text_delta{delta}          — стриминг текста
   (thinking_*-события приходят, но не рисуются)
← tool_execution_start{toolName,args}                   — строка «▸ bash» в ленте
← auto_retry_start/end                                  — индикация ретрая
← message_end.message                                   — АВТОРИТЕТНЫЙ текст ответа
   (wire-дельты только для живого стрима; итог берётся отсюда)
← agent_settled                                         — агент закончил
```

Диалоги extension: `extension_ui_request{method: confirm|select|input|editor}`
→ карточка в чате → `extension_ui_response`.

## Жизненный цикл процесса

- Ленив **только процесс**: объект-синглтон инстанцируется при загрузке шелла
  (биндинги head/foot слота C — безвредно), но `pi` стартует при первом
  открытии `chat`/`aimgr` (cold start 1–2s один раз).
- Уход с обеих панелей (замена/закрытие слота C) процесс **не убивает**:
  контекст разговора дороже 150–300MB резидентного Node; suspend-механизма в
  rpc нет.
- Внешняя смерть (crash / `kill -9`) → статус `died (rc N)` + кнопка
  **RESTART**; каретка/typing гаснут, недоставленные пузыри помечаются
  «✕ undelivered», частичный стрим остаётся пузырём.
- **Kill** в AgentMgr — SIGTERM, осознанная остановка: статус `stopped`, без
  ошибки; RESTART поднимает заново.
- Висящий запрос не висит вечно: pending-таймаут 30s (sweep 5s) — после него
  статус сбрасывается, процесс можно продолжать использовать.

## Провайдер и модели

Мост читает дефолт из settings.json pi (сейчас eliza/glm-5-3) — **zai не
зашит кодом**. Штатный механизм override: `providerOverride`/`modelOverride`
(и `--provider/--model` в команде старта), смена модели в AgentMgr —
`set_model` по живому процессу.

**Открытый вопрос (SPEC §13)**: endpoint eliza в момент тестов был недоступен
(curl 000) — все живые проверки шли через override `zai/glm-5.3-flash`.
Решить: eliza вернулся (тогда дефолт остаётся) или zai делать дефолтом.

## Диагностика

```
pgrep -af "pi --mode rpc"                # жив ли процесс
qs log | grep -i "\[agent\]"             # мост логирует старт/смерть/таймауты
AgentMgr → RESTART                       # штатный подъём без рестарта демона
```

Если чат молчит: проверь статус-строку (no pi binary / died / pending
timeout), затем `qs log`. Проверять exec-каналы по **qslog**, не по stdout —
ReferenceError в QML наружу не всплывает.
