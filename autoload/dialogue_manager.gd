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

## BGM / SE の置き場所。JSON では "field_theme" のように名前だけで指定できる
## （"res://..." で始まるパスをそのまま書いてもよい）
const BGM_BASE_PATH := "res://assets/audio/bgm/"
const SE_BASE_PATH := "res://assets/audio/se/"
const AUDIO_EXTS := [".ogg", ".wav", ".mp3"]
## "bgm" にこの値を書くと BGM を止める
const BGM_STOP := "stop"

var is_active: bool = false

var _lines: Array = []
var _current_index: int = 0
var _event_data: Dictionary = {}

## イベント開始前に流れていた BGM と再生位置（終了時に戻すため）
var _prev_bgm: AudioStream = null
var _prev_bgm_pos: float = 0.0


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

	# 元の BGM を覚えてから、イベント全体の BGM / SE を鳴らす
	_prev_bgm = AudioManager.current_bgm
	_prev_bgm_pos = AudioManager.get_bgm_position()
	_apply_bgm(_event_data.get("bgm", ""))
	_play_se(_event_data.get("se", ""))

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

	# その行で BGM を変える・SE を鳴らす
	_apply_bgm(raw.get("bgm", ""))
	_play_se(raw.get("se", ""))

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


## "bgm" の値に応じて BGM を切り替える。空や未指定なら何もしない
func _apply_bgm(value: Variant) -> void:
	if not value is String or value == "":
		return
	if value == BGM_STOP:
		AudioManager.stop_bgm()
		return
	var stream := _load_audio(BGM_BASE_PATH, value)
	if stream:
		AudioManager.play_bgm(stream)


func _play_se(value: Variant) -> void:
	if not value is String or value == "":
		return
	AudioManager.play_se(_load_audio(SE_BASE_PATH, value))


## 名前から音声ファイルを探して読み込む。拡張子は省略可
func _load_audio(base_path: String, audio_name: String) -> AudioStream:
	var candidates: Array[String] = []
	if audio_name.begins_with("res://"):
		candidates.append(audio_name)
	else:
		candidates.append(base_path + audio_name)
		for ext in AUDIO_EXTS:
			candidates.append(base_path + audio_name + ext)

	for path in candidates:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	push_warning("DialogueManager: 音声ファイルが見つかりません: %s" % audio_name)
	return null


func _finish() -> void:
	# "restore_bgm": false と書いたイベントは、変えた BGM をそのまま流し続ける
	if _event_data.get("restore_bgm", true):
		AudioManager.play_bgm(_prev_bgm, _prev_bgm_pos)
	_prev_bgm = null

	is_active = false
	_lines = []
	_event_data = {}
	dialogue_finished.emit()
