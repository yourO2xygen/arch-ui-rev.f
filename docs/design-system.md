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
- **SegBar** — сегментные полосы метрик (cpu/mem-ячейки SysInfo 228×92).
- **Dot** — статусная точка; пульс (Motion.dotPulse) только у filled-варианта.
- **Field** — текстовое поле: каретка Rectangle 8×2, blink 1070ms + пауза 900ms.
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
