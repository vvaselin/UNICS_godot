## カメラとプレイヤーの間にある遮蔽物をディザリングで透過させるスクリプト
## Camera3D ノードにアタッチして使う
##
## 対応ノード:
##   - StaticBody3D + 子 Sprite3D （家など）
##   - CSGShape3D（CSGBox3D, CSGMesh3D 等の壁）
extends Camera3D

## プレイヤーノード（未設定なら親ノードを自動検出）
@export var player: CharacterBody3D

## 遮蔽時のフェード値 (0.0=完全透明, 1.0=不透明)
@export_range(0.0, 1.0) var occlude_fade: float = 0.15
## フェードにかかる時間（秒）
@export var fade_duration: float = 0.1

## スプライトのこの値より透明な部分に隠れても、遮蔽とみなさない
@export_range(0.0, 1.0) var sprite_alpha_threshold: float = 0.5

var _dither_shader: Shader = preload("res://shaders/dither_fade.gdshader")

# 現在遮蔽中のオブジェクト管理
# key: collider Node3D
# value: { "targets": Array[GeometryInstance3D], "materials": Array[ShaderMaterial], "original_materials": Array[Material], "tween": Tween }
var _occluded: Dictionary = {}

# 透明度の判定用に、テクスチャの画像データを1回だけ読み込んで保持する
# key: Texture2D, value: Image
var _image_cache: Dictionary = {}


func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var space := get_world_3d().direct_space_state
	var from := global_position
	# プレイヤーの少し上（腰あたり）を狙う
	var to := player.global_position + Vector3(0.0, 0.5, 0.0)

	# --- カメラ→プレイヤー間の全コライダーを収集 ---
	var current_occluders: Array[Node] = []
	var exclude: Array[RID] = [player.get_rid()]

	for i in 20: # 安全上限
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collision_mask = 1 # layer 1 = "world"
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Node3D = result["collider"]
		# スプライトの家などは、コリジョン形状が絵より大きい（奥行きがある）ことが多く、
		# 絵に被る前からレイが当たってしまう。そのため見た目での判定
		# (_add_sprite_visual_occluders) だけに任せ、ここでは CSG だけを扱う
		if collider is CSGShape3D:
			current_occluders.append(collider)
		# collider.get_rid() は CSGShape3D で使えないので
		# レイキャスト結果のボディ RID を直接使う
		exclude.append(result["rid"])

	_add_sprite_visual_occluders(current_occluders, from, to)

	# --- もう遮蔽していないオブジェクトを復元 ---
	for obj in _occluded.keys():
		if not is_instance_valid(obj):
			_occluded.erase(obj)
			continue
		if obj not in current_occluders:
			_fade_to(obj, 1.0)

	# --- 新たに遮蔽しているオブジェクトをフェードアウト ---
	for obj in current_occluders:
		if obj not in _occluded:
			_setup_occluder(obj)
		_fade_to(obj, occlude_fade)


## ノードの子から Sprite3D をすべて探す
func _find_sprites(node: Node) -> Array[Sprite3D]:
	var sprites: Array[Sprite3D] = []
	for child in node.get_children():
		if child is Sprite3D:
			sprites.append(child)
	return sprites


func _add_sprite_visual_occluders(current_occluders: Array[Node], from: Vector3, to: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_collect_sprite_visual_occluders(root, current_occluders, from, to)


func _collect_sprite_visual_occluders(node: Node, current_occluders: Array[Node], from: Vector3, to: Vector3) -> void:
	if node is StaticBody3D:
		var body := node as StaticBody3D
		for sprite in _find_sprites(body):
			if _sprite_intersects_segment(sprite, from, to):
				if body not in current_occluders:
					current_occluders.append(body)
				break

	for child in node.get_children():
		_collect_sprite_visual_occluders(child, current_occluders, from, to)


func _sprite_intersects_segment(sprite: Sprite3D, from: Vector3, to: Vector3) -> bool:
	if sprite.texture == null:
		return false

	var segment := to - from
	var segment_length := segment.length()
	if segment_length <= 0.0:
		return false

	var direction := segment / segment_length
	var normal := sprite.global_transform.basis.z.normalized()
	var denominator := normal.dot(direction)
	if absf(denominator) < 0.0001:
		return false

	var distance := normal.dot(sprite.global_position - from) / denominator
	if distance <= 0.0 or distance >= segment_length:
		return false

	var hit := from + direction * distance
	var local_hit := sprite.to_local(hit)

	# 表示しているフレームの範囲（テクスチャ上のピクセル）
	var frame_rect := _get_sprite_frame_rect(sprite)
	var sprite_size := frame_rect.size * sprite.pixel_size
	var offset := sprite.offset * sprite.pixel_size

	var min_point: Vector2 = offset
	if sprite.centered:
		min_point = -sprite_size * 0.5 + offset

	# 絵の四角形の中での位置 (0〜1)。3D の y は上向き、画像の y は下向きなので反転する
	var u := (local_hit.x - min_point.x) / sprite_size.x
	var v := 1.0 - (local_hit.y - min_point.y) / sprite_size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return false
	if sprite.flip_h:
		u = 1.0 - u
	if sprite.flip_v:
		v = 1.0 - v

	# 四角形の中でも、透明な部分なら遮蔽していない
	return _get_alpha(sprite.texture, frame_rect, Vector2(u, v)) >= sprite_alpha_threshold


## Sprite3D が今表示している範囲（region / hframes / vframes を考慮）
func _get_sprite_frame_rect(sprite: Sprite3D) -> Rect2:
	var rect := Rect2(Vector2.ZERO, sprite.texture.get_size())
	if sprite.region_enabled:
		rect = sprite.region_rect
	var frame_size := rect.size / Vector2(sprite.hframes, sprite.vframes)
	var coords := Vector2(sprite.frame_coords)
	return Rect2(rect.position + coords * frame_size, frame_size)


## テクスチャの指定位置の透明度。画像が読めない場合は不透明として扱う
func _get_alpha(texture: Texture2D, frame_rect: Rect2, uv: Vector2) -> float:
	var image: Image = _image_cache.get(texture)
	if image == null:
		image = texture.get_image()
		if image == null:
			return 1.0
		if image.is_compressed():
			image.decompress()
		_image_cache[texture] = image

	var pixel := frame_rect.position + uv * frame_rect.size
	var x := clampi(int(pixel.x), 0, image.get_width() - 1)
	var y := clampi(int(pixel.y), 0, image.get_height() - 1)
	return image.get_pixel(x, y).a


## 初めて遮蔽されたオブジェクトにシェーダーマテリアルを適用
func _setup_occluder(obj: Node3D) -> void:
	var targets: Array[GeometryInstance3D] = []
	var materials: Array[ShaderMaterial] = []
	var original_materials: Array[Material] = []

	if obj is CSGShape3D:
		# --- CSG 壁 ---
		var csg := obj as CSGShape3D
		var mat := _create_fade_material()
		_apply_csg_material_params(csg, mat)
		targets.append(csg)
		materials.append(mat)
		original_materials.append(csg.material_override)
	else:
		# --- StaticBody3D + Sprite3D ---
		var sprites := _find_sprites(obj)
		if sprites.is_empty():
			return
		for sprite in sprites:
			var mat := _create_fade_material()
			mat.set_shader_parameter("albedo_texture", sprite.texture)
			mat.set_shader_parameter("alpha_cutoff", 0.5)
			targets.append(sprite)
			materials.append(mat)
			original_materials.append(sprite.material_override)

	for i in targets.size():
		targets[i].material_override = materials[i]

	_occluded[obj] = {
		"targets": targets,
		"materials": materials,
		"original_materials": original_materials,
		"tween": null,
	}


func _create_fade_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _dither_shader
	mat.set_shader_parameter("fade", 1.0)
	return mat


## CSGShape3D の既存マテリアルからテクスチャ・色を抽出してシェーダーに渡す
func _apply_csg_material_params(csg: CSGShape3D, shader_mat: ShaderMaterial) -> void:
	shader_mat.set_shader_parameter("alpha_cutoff", 0.0)  # 壁は不透明

	# CSGPrimitive3D (CSGBox3D, CSGCylinder3D 等) は material プロパティを持つ
	var original: Material = null
	if csg is CSGPrimitive3D:
		original = csg.material

	if original is StandardMaterial3D:
		var std := original as StandardMaterial3D
		shader_mat.set_shader_parameter("albedo_tint", std.albedo_color)
		if std.albedo_texture != null:
			shader_mat.set_shader_parameter("albedo_texture", std.albedo_texture)
	elif original is ShaderMaterial:
		# 既にカスタムシェーダーなら albedo_tint だけ白にしておく
		shader_mat.set_shader_parameter("albedo_tint", Color.WHITE)
	else:
		# マテリアル未設定 → デフォルト白
		shader_mat.set_shader_parameter("albedo_tint", Color.WHITE)


## fade 値を Tween でスムーズに変化させる
func _fade_to(obj: Node3D, target: float) -> void:
	if obj not in _occluded:
		return

	var info: Dictionary = _occluded[obj]
	var materials: Array[ShaderMaterial] = info["materials"]
	if materials.is_empty():
		_occluded.erase(obj)
		return

	var mat: ShaderMaterial = materials[0]
	var current_fade: float = mat.get_shader_parameter("fade")

	# 既に目標値ならスキップ
	if is_equal_approx(current_fade, target):
		return

	# 既存の Tween をキャンセル
	if info["tween"] != null and info["tween"].is_valid():
		info["tween"].kill()

	var tw := create_tween()
	tw.tween_method(
		_set_materials_fade.bind(materials),
		current_fade, target, fade_duration
	)

	# 完全に不透明に戻ったら後片付け
	if is_equal_approx(target, 1.0):
		tw.tween_callback(func() -> void:
			if is_instance_valid(obj) and obj in _occluded:
				var targets: Array[GeometryInstance3D] = info["targets"]
				var original_materials: Array[Material] = info["original_materials"]
				for i in targets.size():
					var tgt := targets[i]
					if is_instance_valid(tgt):
						tgt.material_override = original_materials[i]
				_occluded.erase(obj)
		)

	info["tween"] = tw


func _set_materials_fade(value: float, materials: Array[ShaderMaterial]) -> void:
	for fade_mat in materials:
		fade_mat.set_shader_parameter("fade", value)
