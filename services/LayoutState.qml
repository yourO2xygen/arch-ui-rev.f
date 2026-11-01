pragma Singleton
// ARCH·UI v2 — services/LayoutState.qml (SPEC §2)
// Менеджер слотов: {A,B,C,bar} → panelId|"bar"|null; toggle/openIn/closeSlot.
// Хореография (выход 180 / новая на +120 / ghost только из пустого) живёт в kit/Panel.qml —
// здесь только состояние. Открытые слоты переживают авторелоад (PersistentProperties,
// reloadableId "layout", SPEC §1).

import QtQuick
import Quickshell

Singleton {
    id: root

    // panelId → слот (раскладка SPEC §0/§2). Панели вне этой сетки пока не существуют
    // (задачи 3/4) — toggle по ним пишёт заглушку в лог.
    readonly property var panelSlots: ({
        docker: "A", taskmgr: "A", sysinfo: "A",
        launcher: "B", logout: "B",
        chat: "C", aimgr: "C", notifcenter: "C"
    })

    // Персист: "" (слот закрыт) / panelId; бар и DND — bool.
    PersistentProperties {
        id: persist
        reloadableId: "layout"
        property string slotA: ""
        property string slotB: ""
        property string slotC: ""
        property bool barOpen: false
        property bool dnd: false
    }

    // Каноническое состояние для окон: A/B/C → panelId|null, bar → "bar"|null.
    readonly property var slots: ({
        A: persist.slotA === "" ? null : persist.slotA,
        B: persist.slotB === "" ? null : persist.slotB,
        C: persist.slotC === "" ? null : persist.slotC,
        bar: persist.barOpen ? "bar" : null
    })

    readonly property bool dnd: persist.dnd

    function slotOf(panelId) {
        const s = root.panelSlots[panelId]
        return s === undefined ? null : s
    }

    function toggle(panelId) {
        const slot = slotOf(panelId)
        if (slot === null) {
            console.warn(`[archui] toggle("${panelId}"): панели нет в сетке слотов — заглушка (задачи 3/4)`)
            return
        }
        if (root.slots[slot] === panelId) closeSlot(slot)
        else openIn(slot, panelId)
    }

    function openIn(slot, panelId) {
        if (root.slots[slot] === panelId) return
        const replacing = root.slots[slot] !== null
        console.info(`[archui] open "${panelId}" → slot ${slot}` +
                     (replacing ? ` (replace "${root.slots[slot]}")` : ""))
        _set(slot, panelId)
    }

    function closeSlot(slot) {
        if (root.slots[slot] === null) return
        console.info(`[archui] close slot ${slot} ("${root.slots[slot]}")`)
        _set(slot, "")
    }

    function toggleBar() {
        persist.barOpen = !persist.barOpen
        console.info("[archui] bar " + (persist.barOpen ? "open" : "closed"))
    }

    // Автоскрытие бара по таймауту (Motion.barTimeout, зовёт components/StatusBar).
    function closeBar() {
        if (!persist.barOpen) return
        persist.barOpen = false
        console.info("[archui] bar closed (timeout)")
    }

    function setDnd(on) {
        persist.dnd = on
        console.info("[archui] dnd " + (on ? "on" : "off"))
    }

    function _set(slot, panelId) {
        if (slot === "A") persist.slotA = panelId
        else if (slot === "B") persist.slotB = panelId
        else if (slot === "C") persist.slotC = panelId
        else console.warn("[archui] unknown slot: " + slot)
    }
}
