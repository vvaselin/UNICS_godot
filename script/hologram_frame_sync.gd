@tool
extends Node
## 親の AnimatedSprite3D の現在フレームの画像を、ホログラムシェーダーに渡す。
## AnimatedSprite3D の子ノードとして置く。@tool なのでエディタ上でも表示が更新される。

## 対象の AnimatedSprite3D。空なら親ノードを使う
@export var target: AnimatedSprite3D


func _ready() -> void:
	if target == null:
		target = get_parent() as AnimatedSprite3D
	if target == null:
		push_warning("HologramFrameSync: AnimatedSprite3D が見つかりません")
		return

	# 実行時だけ、マテリアルを複製して他のノードと共有しないようにする
	# （エディタで複製するとシーンの保存内容が変わってしまうため）
	if not Engine.is_editor_hint() and target.material_override:
		target.material_override = target.material_override.duplicate()

	for sig in [target.frame_changed, target.animation_changed, target.sprite_frames_changed]:
		if not sig.is_connected(_update_hologram_texture):
			sig.connect(_update_hologram_texture)
	_update_hologram_texture()


func _update_hologram_texture() -> void:
	if target == null:
		return
	var mat := target.material_override as ShaderMaterial
	var frames := target.sprite_frames
	if mat == null or frames == null or not frames.has_animation(target.animation):
		return

	var tex: Texture2D = frames.get_frame_texture(target.animation, target.frame)
	if tex == null:
		return

	# スプライトシートから切り出したフレーム（AtlasTexture）の場合は、
	# 元の画像全体と、その中でのフレームの範囲を渡す
	var region := Vector4(0.0, 0.0, 1.0, 1.0)
	var atlas_tex := tex as AtlasTexture
	if atlas_tex and atlas_tex.atlas:
		var size := atlas_tex.atlas.get_size()
		var r := atlas_tex.region
		region = Vector4(r.position.x / size.x, r.position.y / size.y, r.size.x / size.x, r.size.y / size.y)
		tex = atlas_tex.atlas

	mat.set_shader_parameter("sprite_texture", tex)
	mat.set_shader_parameter("frame_region", region)
