extends Node3D

@onready var sprite: AnimatedSprite3D = $".." 

var shadow_material: ShaderMaterial

func _ready() -> void:
	# シェーダーマテリアルを作成
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = preload("res://shaders/sprite_shadow.gdshader")
	self.material_override = shadow_material

	_sync_texture()
	sprite.frame_changed.connect(_sync_uv)

func _sync_texture() -> void:
	var frames = sprite.sprite_frames
	var anim   = sprite.animation
	var frame  = sprite.frame
	var tex    = frames.get_frame_texture(anim, frame)
	shadow_material.set_shader_parameter("sprite_texture", tex)
	_sync_uv()

func _sync_uv() -> void:
	var frames  = sprite.sprite_frames
	var anim    = sprite.animation
	var frame   = sprite.frame
	var tex     = frames.get_frame_texture(anim, frame)

	# AnimatedSprite3D はフレームごとに別テクスチャの場合もあるので更新
	shadow_material.set_shader_parameter("sprite_texture", tex)

	# スプライトシート（hframes/vframes）の場合はUV計算が必要
	# 個別テクスチャならuv_offset=(0,0), uv_scale=(1,1)のままでOK
	shadow_material.set_shader_parameter("uv_offset", Vector2(0.0, 0.0))
	shadow_material.set_shader_parameter("uv_scale",  Vector2(1.0, 1.0))
