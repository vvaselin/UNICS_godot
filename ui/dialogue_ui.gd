## DialogueUI
## Autoload ではなく、main.tscn の CanvasLayer の子としてインスタンス化する
##
## 期待するノード構造（名前は変えないこと、配置は自由）:
##   DialogueUI (Control)  ← このスクリプトをアタッチ
##   ├── BG       (TextureRect)  背景画像
##   ├── Portrait (TextureRect)  ポートレート
##   └── Box      (任意のコンテナ or Panel)
##       ├── NameLabel (Label)  キャラ名
##       ├── TextLabel (Label)  セリフ
##       └── Cursor    (Label)  ▼ カーソル
extends Control

@onready var _portrait: TextureRect = $Portrait
@onready var _name_lbl: Label       = $Box/NameLabel
@onready var _text_lbl: Label       = $Box/TextLabel
@onready var _cursor:   Label       = $Box/Cursor

## タイプライター速度（1文字あたりの秒数 / 0.0 で即表示）
@export var text_speed: float = 0.03

var _full_text: String = ""
var _is_typing:  bool   = false
var _tween: Tween       = null


func _ready() -> void:
	hide()
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.line_changed.connect(_on_line_changed)
	DialogueManager.dialogue_finished.connect(_on_dialogue_finished)


# ── シグナルハンドラ ─────────────────────────────────────

func _on_dialogue_started() -> void:
	show()


func _on_line_changed(line: Dictionary) -> void:

	# ポートレート
	var portrait_path: String = line.get("portrait", "")
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		_portrait.texture = load(portrait_path)
		_portrait.visible = true
	else:
		_portrait.texture = null
		_portrait.visible = false

	# 名前
	_name_lbl.text = line.get("name", "")

	# セリフ（タイプライター）
	_full_text = line.get("text", "")
	_start_typewriter()


func _on_dialogue_finished() -> void:
	hide()

# ── タイプライター ────────────────────────────────────────

func _start_typewriter() -> void:
	_cursor.visible = false
	_text_lbl.text  = ""

	if text_speed <= 0.0:
		_text_lbl.text  = _full_text
		_cursor.visible = true
		_is_typing      = false
		return

	_is_typing = true
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_method(
		func(n: int) -> void: _text_lbl.text = _full_text.left(n),
		0, _full_text.length(),
		text_speed * _full_text.length()
	)
	_tween.tween_callback(func() -> void:
		_text_lbl.text  = _full_text
		_is_typing      = false
		_cursor.visible = true
	)


# ── 入力 ─────────────────────────────────────────────────
# _input が _unhandled_input より先に処理されるため、
# ここで set_input_as_handled() を呼ぶと interactable._unhandled_input をブロックできる

func _input(event: InputEvent) -> void:
	if not visible or not DialogueManager.is_active:
		return

	var is_advance := (
		event.is_action_pressed("ui_accept")
		or (InputMap.has_action("INTERACT") and event.is_action_pressed("INTERACT"))
	)
	if not is_advance:
		return

	get_viewport().set_input_as_handled()

	if _is_typing:
		if _tween and _tween.is_valid():
			_tween.kill()
		_text_lbl.text  = _full_text
		_is_typing      = false
		_cursor.visible = true
	else:
		DialogueManager.advance()
