# Дизайн-система

Два синглтона — Theme.qml (цвета/шрифты/отступы) и Motion.qml (движение, см.
[motion.md](motion.md)) — **единственные** места токенов. Значения в
компонентах не хардкодятся.

## Токены Theme

| Токен | Значение | Смысл |
|---|---|---|
| `surface` | #000000 | фон |
| `txt` / `txt2` | #f4f4f5 / #a1a1aa | основной / вторичный текст |
| `dim` / `ghost` | #56565e / #3f3f46 | приглушённый / контурный |
| `raise` / `raise2` | white 5% / 9% | hover-подложки |
| `invBg` / `invFg` | #f4f4f5 / #000000 | инверсия (выделение, ERROR-строки) |
| `ghostLine` | white 50% | контуры ghost-анимаций |
| `strokeE` | 1.5 | effective stroke иконок: `stroke_vb = strokeE·24/size`, пол 1.25 |
| отступы | s6…s18 | 6/8/10/11/12/13/18 — фактические значения макета (шкала «кратно 4» не соблюдалась — переносили факт) |
| отступы (паддинги) | `s16` | 16 — паддинг панелей (kit/Panel `padLeft`) |
| шрифты (pixelSize) | `fs8`…`fs18` | базы 10/11/13/14/15/13/15/18 (эффективные при px≈1.04: 10/11/14/15/15/13/15/18) — Task 24: контент +25%, fs15/fs18 были уже у эталона, fs13 — только Placeholder; все `font.pixelSize` в компонентах ссылаются только сюда. Исключение: значения Docker resources — fs9 (живая полоса + 20-симв. значение не делят ≤284px) |
| высоты структур | `hHead` 40, `hFoot` 30 | head/foot-кит слота (kit/Panel) |
| высоты рядов | `hRow` 30, `hRowL` 34, `hRowS` 28 | панельные ряды (TaskMgr/AgentMgr/AgentChat/Docker) / крупные (Launcher) / компактные (kit/Row, hw-строки SysInfo) |
| высота чипов/плиток | `hChip` | 22 — чипы, мини-плитки, кнопки |
| слот B (Task 24) | `hDock` 48, `hTile` 64, `hSlotB` = hDock+4·hRowL | dock лаунчера / плитки logout (было 56 фикс) / высота окна лаунчера стадии 2 |
| бар (Task 24) | `wBar` 360, `barPad` 18 | окно статус-бара (было 500) / поле от краёв бара |
| ширина метки | `wLabel` | 84 — метка-колонка label caps (Docker info, SysInfo hw) |
| радиус | `r2` | 2 — скругление чипов/баблов |
| `font` | "JetBrainsMono NFM" | системный 400–700, FontLoader не нужен |
| `fontDseg` | DSEG7Classic-Bold | FontLoader из assets/fonts |
| `glass` | false | false **не создаёт** текстуры стекла вообще (не просто прячет) |
| `glitch` | true | false отключает GPU-шейдер глича целиком (остаётся lite-flicker) |

## Примитивы kit

Правило: примитив добавляется вторым использованием. `Row`, `Chip`, `Btn`,
`SegBar`, `Dot`, `Field`, `Section`, `Panel`, `Icon`, `GlitchFX`.

- **Panel** — каркас слота: head 40 / body (pad 12·16·16) / foot 30, вся
  хореография открытия/замены/закрытия, ghost-эхо, глич, маска ввода,
  keyboardFocus (OnDemand; лаунчер переопределяет на Exclusive), overlay-слот.
  Панелям-компонентам **свои margins не нужны** — body уже даёт pad
  (дублирование уезжает за край, ловится только скриншотом).
- **Row** — строка списка: hover raise, selected inset, dot-слот.
- **Chip** — чип-пилюля (дата-чип календаря, чипы сортировки).
- **Btn** — кнопка (инверсия по hover; enabled-состояние цветом поля, без
  border-фокуса).
- **SegBar** — сегментные полосы метрик (ячейки SysInfo f(228)×f(96), Task 24).
- **Dot** — статусная точка; пульс (Motion.dotPulse) только у filled-варианта.
- **Field** — текстовое поле: каретка Rectangle 3×h, blink 1070ms + пауза 900ms;
  высота по умолчанию `hRowL` (Task 24: каретка 9×2→3, было 34 фикс).
- **Section** — заголовок секции.
- **Icon** — Lucide path → Shape/ShapePath (retained-дерево, не Canvas;
  перерастеризации нет). Набор — assets/icons.json.
- **GlitchFX** — монохромный глич, см. [motion.md](motion.md).

## Правила импорта

Импорт kit — **только namespaced**: `import "../kit" as Kit`. Директория-импорт
затеняет `QtQuick.Row` — без неймспейса `Row` в файле ломается. Inline
`component X: …` в файле с таким импортом используется **без** префикса.

## Известные Qt-грабли (не наступать)

- `border.width`-фокус-ринги на прозрачных Rect — QTBUG-137166: фокус
  показываем цветом поля, без border.
- anchors на детях Column/Row → «Column will not function», все дети ложатся в
  (0,0): отступы в positioner-детях — только padding.
- `property` и `function` с одним именем в синглтоне: вызов уходит в property
  (null), TypeError молча. Не переименновывать наполовину.
- `Qt.formatDateTime` c QLocale-оверлоадом в Qt 6.12 не работает — формат
  дат через components/datefmt.js.

## Шейдеры глича (пересборка)

Qt 6 ShaderEffect **не принимает inline GLSL** — молча рендерит пустоту
(«Failed to find shader» только в qslog). Исходники и скомпилированные
бинарники лежат рядом: `kit/shaders/glitch.{vert,frag}` + `.qsb`.

Пересборка после правки GLSL:

```
/usr/lib/qt6/bin/qsb kit/shaders/glitch.vert -o kit/shaders/glitch.vert.qsb
/usr/lib/qt6/bin/qsb kit/shaders/glitch.frag -o kit/shaders/glitch.frag.qsb
```

(`qsb` — пакет qt6-shadertools.) Затем **полный рестарт демона**.
