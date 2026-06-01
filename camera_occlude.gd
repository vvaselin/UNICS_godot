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

var _dither_shader: Shader = preload("res://shaders/dither_fade.gdshader")

# 現在遮蔽中のオブジェクト管理
# key: collider Node3D
# value: { "target": Node3D (material_override先), "material": ShaderMaterial, "tween": Tween }
var _occluded: Dictionary = {}


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
		if _can_occlude(collider):
			current_occluders.append(collider)
		# collider.get_rid() は CSGShape3D で使えないので
		# レイキャスト結果のボディ RID を直接使う
		exclude.append(result["rid"])

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


## このコライダーをディザ対象にできるか判定
func _can_occlude(node: Node) -> bool:
	# CSGShape3D（CSGBox3D, CSGMesh3D 等）
	if node is CSGShape3D:
		return true
	# StaticBody3D で子に Sprite3D があるもの
	if node is StaticBody3D:
		return _find_sprite(node) != null
	return false


## ノードの子から Sprite3D を探す
func _find_sprite(node: Node) -> Sprite3D:
	for child in node.get_children():
		if child is Sprite3D:
			return child
	return null


## 初めて遮蔽されたオブジェクトにシェーダーマテリアルを適用
func _setup_occluder(obj: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _dither_shader
	mat.set_shader_parameter("fade", 1.0)

	var target_node: Node3D  # material_override を設定するノード

	if obj is CSGShape3D:
		# --- CSG 壁 ---
		target_node = obj
		_apply_csg_material_params(obj, mat)
	else:
		# --- StaticBody3D + Sprite3D ---
		var sprite := _find_sprite(obj)
		if sprite == null:
			return
		target_node = sprite
		mat.set_shader_parameter("albedo_texture", sprite.texture)
		mat.set_shader_parameter("alpha_cutoff", 0.5)

	target_node.material_override = mat

	_occluded[obj] = {
		"target": target_node,
		"material": mat,
		"tween": null,
	}


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
	var mat: ShaderMaterial = info["material"]
	var current: float = mat.get_shader_parameter("fade")

	# 既に目標値ならスキップ
	if is_equal_approx(current, target):
		return

	# 既存の Tween をキャンセル
	if info["tween"] != null and info["tween"].is_valid():
		info["tween"].kill()

	var tw := create_tween()
	tw.tween_method(
		func(val: float) -> void: mat.set_shader_parameter("fade", val),
		current, target, fade_duration
	)

	# 完全に不透明に戻ったら後片付け
	if is_equal_approx(target, 1.0):
		tw.tween_callback(func() -> void:
			if is_instance_valid(obj) and obj in _occluded:
				var tgt: Node3D = info["target"]
				if is_instance_valid(tgt):
					tgt.material_override = null
				_occluded.erase(obj)
		)

	info["tween"] = tw
