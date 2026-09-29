// Sprite3D 用ホログラムシェーダー（Godot 4.x）
// 使い方: Sprite3D > GeometryInstance3D > Material Override に ShaderMaterial を設定し、
//         このシェーダーを割り当てて、sprite_texture に Sprite3D と同じテクスチャを入れる。
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// ドット絵なら filter_linear_mipmap を filter_nearest に変える
uniform sampler2D sprite_texture : source_color, filter_linear_mipmap, repeat_disable;
// Material Override を使うと Sprite3D 側の Billboard 設定が効かないので、ここで代わりに行う
uniform bool billboard = false;

group_uniforms Color;
uniform vec4 holo_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.05; // 元の色をどれだけホログラム色に寄せるか
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float glow : hint_range(0.0, 2.0) = 0.3;           // 全体の発光の強さ

group_uniforms Scanline;
uniform float scanline_count = 120.0;                         // 縦方向の本数
uniform float scanline_speed = 1.5;                           // 流れる速さ
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25; // 暗くなる度合い
uniform float sweep_speed = 0.4;                              // 光の帯が通る速さ
uniform float sweep_width : hint_range(0.0, 0.5) = 0.08;
uniform float sweep_strength : hint_range(0.0, 2.0) = 0.5;

group_uniforms Glitch;
uniform float glitch_frequency : hint_range(0.0, 1.0) = 0.12; // グリッチが起きる確率
uniform float glitch_rate = 12.0;                             // 1秒あたりの判定回数
uniform float glitch_offset : hint_range(0.0, 0.2) = 0.03;    // 横ずれの最大量
uniform float glitch_slices = 24.0;                           // 横に切る段数
uniform float chroma_offset : hint_range(0.0, 0.05) = 0.004;  // 色ずれ（グリッチ中は強くなる）
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.08; // ちらつき

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		// ノードのスケールを保つ
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;

	// --- グリッチ: ときどき一部の段だけ横にずらす ---
	float step_t = floor(t * glitch_rate);
	float glitch_on = step(1.0 - glitch_frequency, hash(vec2(step_t, 1.3)));
	float slice = floor(uv.y * glitch_slices);
	float slice_hit = step(0.6, hash(vec2(slice * 1.7, step_t + 3.1)));
	float shift = (hash(vec2(slice, step_t)) - 0.5) * 2.0 * glitch_offset;
	uv.x += shift * glitch_on * slice_hit;

	// --- 色ずれ ---
	float ca = chroma_offset * (1.0 + glitch_on * 3.0);
	vec4 base = texture(sprite_texture, uv);
	float r = texture(sprite_texture, uv + vec2(ca, 0.0)).r;
	float b = texture(sprite_texture, uv - vec2(ca, 0.0)).b;
	vec3 col = vec3(r, base.g, b) * COLOR.rgb; // COLOR = Sprite3D の Modulate
	float a = base.a * COLOR.a;
	a *= step(0.0, uv.x) * step(uv.x, 1.0); // ずれてはみ出た部分は消す

	// --- 元の色を残しつつホログラム色に寄せる ---
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, holo_color.rgb * (lum * 0.8 + 0.2), tint_strength);

	// --- 走査線 ---
	float line = 0.5 + 0.5 * sin((UV.y * scanline_count - t * scanline_speed) * 6.2831853);
	float scan = mix(1.0, line, scanline_strength);
	col *= scan;

	// --- 上下に通る光の帯 ---
	float pos = fract(t * sweep_speed) * (1.0 + sweep_width * 2.0) - sweep_width;
	float band = 1.0 - smoothstep(0.0, max(sweep_width, 0.0001), abs(UV.y - pos));
	col += holo_color.rgb * band * sweep_strength;

	// --- 発光 ---
	col += holo_color.rgb * glow * 0.3;

	// --- ちらつき ---
	float flicker = 1.0 - flicker_strength * hash(vec2(floor(t * 30.0), 7.7));

	ALBEDO = col;
	ALPHA = a * opacity * flicker * mix(1.0, scan, 0.5);
}
