shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Sprite3D のテクスチャ or CSGMesh3D のアルベドテクスチャ（未設定なら白）
uniform sampler2D albedo_texture : source_color, filter_nearest;
// CSGMesh3D の albedo_color 等を乗算するためのティント
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Sprite3D: 0.5 でアルファ抜き / CSGの壁: 0.0 でカットオフなし
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

// 4x4 Bayer ordered dithering — 各ピクセルに閾値を返す
float bayer4(vec2 screen_pos) {
	ivec2 p = ivec2(mod(screen_pos, 4.0));
	int idx = p.x + p.y * 4;
	// 標準 Bayer 4×4 マトリクス (閾値 1/17 ~ 16/17)
	if (idx ==  0) return  1.0 / 17.0;
	if (idx ==  1) return  9.0 / 17.0;
	if (idx ==  2) return  3.0 / 17.0;
	if (idx ==  3) return 11.0 / 17.0;
	if (idx ==  4) return 13.0 / 17.0;
	if (idx ==  5) return  5.0 / 17.0;
	if (idx ==  6) return 15.0 / 17.0;
	if (idx ==  7) return  7.0 / 17.0;
	if (idx ==  8) return  4.0 / 17.0;
	if (idx ==  9) return 12.0 / 17.0;
	if (idx == 10) return  2.0 / 17.0;
	if (idx == 11) return 10.0 / 17.0;
	if (idx == 12) return 16.0 / 17.0;
	if (idx == 13) return  8.0 / 17.0;
	if (idx == 14) return 14.0 / 17.0;
	if (idx == 15) return  6.0 / 17.0;
	return 0.0;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_tint;

	// アルファカットオフ — Sprite3D: 0.5 で透明部分を破棄 / CSG壁: 0.0 で無効
	if (tex.a < alpha_cutoff) {
		discard;
	}

	// ディザリングによるフェード — fade が下がるほど多くのピクセルを破棄
	if (fade < 1.0 && fade < bayer4(FRAGCOORD.xy)) {
		discard;
	}

	// COLOR にはSprite3Dの modulate 等が反映されている
	ALBEDO = tex.rgb * COLOR.rgb;
}
