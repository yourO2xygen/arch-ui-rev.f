// ARCH·UI v2 — kit/GlitchFX.qml (Task 9, DESIGN §5 + примечание юзера п.8)
// Киберпанк-глич появления панели: ShaderEffect, подключается как layer.effect
// (property `source` автосвязывается с layer-текстурой хоста).
//
// Эффекты фрагмента (все — СТРОГО монохром, цветных каналов шейдер не добавляет):
//   (а) построчный x-сдвиг hash(floor(uv.y*N), floor(t*24.));
//   (б) моно-двоение — 2 alpha-выборки со смещением ±2px, яркость краёв усилена;
//   (в) инверсия случайных полос step(.97, hash(row,t)) — по luminance;
//   (г) flicker mix(1., .7+.3*step(.5,hash(t)), envelope);
//   (д) скан-линия вниз.
// envelope = 1 - progress; progress 0→1 за Motion.glitchPanel (350ms).
//
// GPU-гигиена (SPEC §8): шейдер активен ТОЛЬКО пока идёт переход — хост держит
// layer.enabled = live, по окончании панель рендерится обычным путём. Если шейдер
// дороже ~2ms/кадр на этой машине — Theme.glitch=false отключает его (остаётся
// lite-вариант, kit-хосты сами), как Theme.glass для стекла (SPEC §9).

import QtQuick

ShaderEffect {
    id: fx

    // Автосвязка при использовании как layer.effect
    property var source

    // 0 — старт глича, 1 — конец (нейтрально; хост к этому моменту выключает layer)
    property real progress: 1

    // размер в px — для смещения «±2px» в текстурных координатах
    property real widthPx: source ? source.width : 1
    property real heightPx: source ? source.height : 1

    blending: true

    // ⚠ Qt 6: inline GLSL не поддерживается — только .qsb (qsb tool, qt6-shadertools).
    // Источники с комментариями эффектов (а)–(д) см. в kit/shaders/*.frag.vert исходниках
    // задачи (пересборка: /usr/lib/qt6/bin/qsb --qt6 -o x.qsb x.vert|frag).
    vertexShader: "shaders/glitch.vert.qsb"
    fragmentShader: "shaders/glitch.frag.qsb"
}
