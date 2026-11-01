#version 440 core

layout(location = 0) in highp vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform highp sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float widthPx;
    float heightPx;
};

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float env = 1.0 - progress;          // сила глича затухает к концу
    float t = floor(progress * 24.0);    // 24 «кадра» глича за переход
    float row = floor(uv.y * 48.0);      // 48 горизонтальных полос

    // (а) построчный x-сдвиг; редкие строки дёргаются сильнее
    float dx = (hash(vec2(row, t)) - 0.5) * 0.05 * env;
    if (hash(vec2(row * 1.7, t)) > 0.8) dx *= 3.0;
    vec2 uvA = uv + vec2(dx, 0.0);

    // (б) моно-двоение: выборки ±2px, luminance, края ярче
    vec2 px = vec2(2.0 / widthPx, 0.0);
    vec4 c0 = texture(source, uvA);
    vec4 c1 = texture(source, uvA + px);
    vec4 c2 = texture(source, uvA - px);
    float lum = dot(c0.rgb, vec3(0.299, 0.587, 0.114));
    float l1 = dot(c1.rgb, vec3(0.299, 0.587, 0.114));
    float l2 = dot(c2.rgb, vec3(0.299, 0.587, 0.114));
    float edge = clamp(abs(c1.a - c2.a) * 2.0, 0.0, 1.0);
    float l = max(lum, max(l1, l2) * (0.6 + 0.6 * edge));
    float a = max(c0.a, max(c1.a, c2.a));

    // (в) инверсия случайных полос — по luminance (монохром)
    float inv = step(0.97, hash(vec2(row, t + 7.0))) * env;
    l = mix(l, 1.0 - l, inv);

    // (г) flicker
    float fl = mix(1.0, 0.7 + 0.3 * step(0.5, hash(vec2(t, 3.0))), env);

    // (д) скан-линия вниз (позиция = progress)
    float scan = smoothstep(0.03, 0.0, abs(uv.y - progress)) * 0.35 * env;
    l = clamp(l + scan, 0.0, 1.0);

    // progress >= 1 — шейдер строго нейтрален (страховка от «вечного глича»)
    vec3 col = progress >= 1.0 ? c0.rgb : vec3(l * fl);
    float alpha = progress >= 1.0 ? c0.a : a * mix(1.0, fl, 0.5);
    fragColor = vec4(col, alpha) * qt_Opacity;
}
