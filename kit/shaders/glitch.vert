#version 440 core

layout(location = 0) in highp vec4 qt_Vertex;
layout(location = 1) in highp vec2 qt_MultiTexCoord0;
layout(location = 0) out highp vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
