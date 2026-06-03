## DialogueManager (Autoload)
## 会話イベントの状態管理シングルトン
## プロジェクト設定 > AutoLoad に追加: autoload/dialogue_manager.gd → DialogueManager
extends Node

## 会話が始まったとき
signal dialogue_started
## 1行進んだとき（UIがこれを受け取って表示を更新する）
signal line_changed(line_data: Dictionary)
## 会話が終わったとき
signal dialogue_finished

## ポートレート名 → テクスチャパスのマッピング
## 存在しない名前は空欄ポートレートとして扱う
const PORTRAIT_BASE_PATH := "res://assets/portraits/"
const PORTRAIT_EXT := ".png"

var is_active: bool = false

var _lines: Array = []
var _current_index: int = 0
var _event_data: Dictionary = {}


## 外部から呼び出すエントリーポイント
## event_path: "res://data/events/event_01.json" のような絶対パス
func start_event(event_path: String) -> void:
	if is_active:
		return  # 多重起動防止

	var file := FileAccess.open(event_path, FileAccess.READ)
	if file == null:
		push_error("DialogueManager: イベントファイルが見つかりません: %s" % event_path)
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("DialogueManager: JSON パースエラー: %s" % event_path)
		return

	_event_data = json.get_data()
	_lines = _event_data.get("lines", [])
	_current_index = 0
	is_active = true

	dialogue_started.emit()
	_emit_current_line()


## 次の行へ進む（UIのボタン or 入力から呼ぶ）
func advance() -> void:
	if not is_active:
		return

	_current_index += 1
	if _current_index >= _lines.size():
		_finish()
	else:
		_emit_current_line()


## 現在の行データをシグナルで送る
func _emit_current_line() -> void:
	var raw: Dictionary = _lines[_current_index]
	var line: Dictionary = {
		"name":    raw.get("name", ""),
		"portrait": _resolve_portrait(raw.get("portrait", "")),
		"text":    raw.get("text", ""),
		"background": _event_data.get("background", ""),
		"bgm":     _event_data.get("bgm", ""),
	}
	line_changed.emit(line)


## ポートレート名をテクスチャパスに変換
## 名前が空 or ファイルが存在しない場合は "" を返す
func _resolve_portrait(portrait_name: String) -> String:
	if portrait_name == "":
		return ""
	var path := PORTRAIT_BASE_PATH + portrait_name + PORTRAIT_EXT
	if ResourceLoader.exists(path):
		return path
	return ""


func _finish() -> void:
	is_active = false
	_lines = []
	_event_data = {}
	dialogue_finished.emit()
