// ARCH·UI v2 — components/datefmt.js
// Фиксированные англ. сокращения дат (SPEC: `sun · nov 1`, ANALYSIS §7.2 — формат
// даты бара/календаря не локализуется). Qt.formatDateTime(locale, custom) в этой
// сборке не берёт кастомный формат с не-дефолтной локалью — поэтому числа сюда.

var DAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
var MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
              "jul", "aug", "sep", "oct", "nov", "dec"]
var MONTHS_FULL = ["january", "february", "march", "april", "may", "june",
                   "july", "august", "september", "october", "november", "december"]
var WEEKDAYS_FULL = ["sunday", "monday", "tuesday", "wednesday",
                     "thursday", "friday", "saturday"]

// `sun · nov 1` — дата бара и чип календаря
function shortDate(y, m, d) {
    return DAYS[new Date(y, m, d).getDay()] + " · " + MONTHS[m] + " " + d
}

// `nov 1` — чип календаря в развернутом виде
function dayMonth(m, d) {
    return MONTHS[m] + " " + d
}

// `nov 1 · november` — свернутый чип (дата + месяц)
function chipFull(y, m, d) {
    return MONTHS[m] + " " + d + " · " + MONTHS_FULL[m]
}

// `November 2026` — навигатор календаря (с большой буквы, как в макете)
function monthTitle(y, m) {
    var full = MONTHS_FULL[m]
    return full.charAt(0).toUpperCase() + full.slice(1) + " " + y
}

// `05` — counter-номер дня (REV.D-F date-band), 2 цифры, tabular (mono-шрифт)
function dateCounter(d) {
    return ("0" + d).slice(-2)
}

// `THURSDAY` — день недели caps, строка над подписью date-band
function weekdayFullCaps(date) {
    return WEEKDAYS_FULL[date.getDay()].toUpperCase()
}

// `november 2026 · week 45` — месяц год · ISO-неделя, подпись date-band
function monthWeekFull(y, m, w) {
    return MONTHS_FULL[m] + " " + y + " · week " + w
}

// `2026·11` — foot календаря (год·месяц отображаемой сетки, ghost)
function monthYearCompact(y, m) {
    return y + "·" + ("0" + (m + 1)).slice(-2)
}
