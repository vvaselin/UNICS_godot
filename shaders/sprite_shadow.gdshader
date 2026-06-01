shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color;
uniform vec2 uv_offset = vec2(0.0, 0.0);   // フレームのUV開始位置
uniform vec2 uv_scale  = vec2(1.0, 1.0);   // フレームのUVサイズ
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform float shadow_sharpness : hint_range(0.1, 1.0) = 0.8;

void fragment() {
    vec2 uv = UV * uv_scale + uv_offset;
    float alpha = texture(sprite_texture, uv).a;

    // エッジをシャープに or ソフトに調整
    alpha = smoothstep(1.0 - shadow_sharpness, 1.0, alpha);

    ALBEDO = shadow_color.rgb;
    ALPHA  = alpha * shadow_color.a;
}