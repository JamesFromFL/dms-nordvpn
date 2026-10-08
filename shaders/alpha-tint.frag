#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    // Qt supplies premultiplied color uniforms. Keep only the original alpha;
    // the PNG's RGB and luminance must never darken the selected theme color.
    fragColor = tint * texture(source, qt_TexCoord0).a * qt_Opacity;
}
