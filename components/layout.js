// ARCH·UI v2 — components/layout.js
// Транслитерация ЙЦУКЕН↔QWERTY (Task 23): запрос, набранный в неверной
// раскладке («ашкуащч» — те же клавиши, что f-i-r-e-f-o-x), находит «firefox».
// Таблица позиционная и биективная (заглавные через toUpperCase), поэтому одна
// функция translit работает в обе стороны; конвертация посимвольная — смешанный
// ввод (часть латиницей, часть кириллицей) конвертируется естественно, символы
// вне таблицы — как есть. Размещение — как у datefmt.js: JS-утилиты живут в
// components/, импорт рядом с потребителем (см. Launcher.qml).

var PAIRS = [
    ["й", "q"], ["ц", "w"], ["у", "e"], ["к", "r"], ["е", "t"],
    ["н", "y"], ["г", "u"], ["ш", "i"], ["щ", "o"], ["з", "p"],
    ["ф", "a"], ["ы", "s"], ["в", "d"], ["а", "f"], ["п", "g"],
    ["р", "h"], ["о", "j"], ["л", "k"], ["д", "l"],
    ["я", "z"], ["ч", "x"], ["с", "c"], ["м", "v"], ["и", "b"],
    ["т", "n"], ["ь", "m"], ["б", ","], ["ю", "."]
]

var MAP = {}
for (var pi = 0; pi < PAIRS.length; pi++) {
    MAP[PAIRS[pi][0]] = PAIRS[pi][1]
    MAP[PAIRS[pi][0].toUpperCase()] = PAIRS[pi][1].toUpperCase()
    MAP[PAIRS[pi][1]] = PAIRS[pi][0]
    MAP[PAIRS[pi][1].toUpperCase()] = PAIRS[pi][0].toUpperCase()
}

// «ашкуащч» → «firefox», «firef» → «ашеуа»; прочие символы — без изменений
function translit(s) {
    var out = ""
    for (var i = 0; i < s.length; i++) {
        var c = s[i]
        out += (MAP[c] !== undefined) ? MAP[c] : c
    }
    return out
}

// Матчинг имени по подстроке в обеих раскладках. q/qt — уже lowercase
// (нормализация вызывающего), qt = translit(q), считается один раз на фильтрацию.
function matches(q, qt, name) {
    return name.indexOf(q) !== -1 || name.indexOf(qt) !== -1
}
