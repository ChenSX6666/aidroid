#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_touch;
uniform float u_press;
uniform sampler2D sTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution;

    // Refraction distortion - subtle wave effect
    float distort = sin(uv.y * 20.0 + u_time * 2.0) * 0.002;
    float distort2 = cos(uv.x * 15.0 + u_time * 1.5) * 0.002;
    vec2 uvDistorted = uv + vec2(distort, distort2);

    // Chromatic aberration - slight RGB channel offset
    float r = texture(sTexture, uvDistorted + vec2(0.001, 0.0)).r;
    float g = texture(sTexture, uvDistorted).g;
    float b = texture(sTexture, uvDistorted - vec2(0.001, 0.0)).b;
    vec4 color = vec4(r, g, b, 0.85);

    // Liquid shimmer highlight
    float shimmer = sin(uv.x * 10.0 + uv.y * 8.0 + u_time * 3.0) * 0.5 + 0.5;
    shimmer = smoothstep(0.6, 0.9, shimmer) * 0.12;
    color.rgb += shimmer;

    // Press ripple effect
    if (u_press > 0.01) {
        float dist = distance(uv, u_touch);
        float ripple = sin(dist * 40.0 - u_time * 8.0) * 0.5 + 0.5;
        ripple *= exp(-dist * 10.0) * u_press * 0.25;
        color.rgb += ripple;
    }

    // Edge highlight (glass rim glow)
    float edgeX = smoothstep(0.0, 0.02, uv.x) * smoothstep(0.0, 0.02, 1.0 - uv.x);
    float edgeY = smoothstep(0.0, 0.02, uv.y) * smoothstep(0.0, 0.02, 1.0 - uv.y);
    float edge = edgeX * edgeY;
    color.rgb = mix(color.rgb * 1.15, color.rgb, edge);

    fragColor = color;
}
