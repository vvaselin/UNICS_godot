## Interactable (Area3D にアタッチ)
## 調べられるオブジェクト用スクリプト
##
## なぜ _unhandled_input を使うか:
##   _process + Input.is_action_just_pressed() は set_input_as_handled() を無視するため、
##   DialogueUI が「処理済み」にしたキーでも反応してしまい、最終行で会話が再起動する。
##   _unhandled_input は handled 済みの入力が届かないので、この問題を根本的に回避できる。
extends Area3D

## 発火するイベントファイルのパス
@export_file("*.json") var event_path: String = ""

## プレイヤーのコリジョンレイヤー（インスペクターでチェックを付けて選ぶ）
@export_flags_3d_physics var player_layer: int = 2

## [オプション] 範囲内にいることを示すヒント UI
@export var hint_node: Control = null

var _player_in_range: bool = false


func _ready() -> void:
	collision_layer = 0        # Area3D 自体はどのレイヤーにも属さない
	collision_mask  = player_layer  # プレイヤーレイヤーのみ検出

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if hint_node:
		hint_node.visible = false


## handled 済みの入力は届かないため DialogueUI が処理した E キーには反応しない
func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if event_path == "":
		return

	var is_interact := (
		(InputMap.has_action("INTERACT") and event.is_action_pressed("INTERACT"))
	)
	if not is_interact:
		return

	DialogueManager.start_event(event_path)
	# 自分の入力も handled にして他ノードに伝播させない
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.collision_layer & player_layer:
		_player_in_range = true
		if hint_node:
			hint_node.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.collision_layer & player_layer:
		_player_in_range = false
		if hint_node:
			hint_node.visible = false
