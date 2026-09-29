shader_type sky;

uniform sampler2D sky_background : filter_linear, source_color;
uniform float exposure : hint_range(0.0, 8.0) = 1.0;

void sky() {
    vec2 uv = SKY_COORDS;

    // 横方向に180度回転
    uv.x = fract(uv.x + 0.5);

    COLOR = texture(sky_background, uv).rgb * exposure;
}