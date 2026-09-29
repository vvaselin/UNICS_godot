## AudioManager（Autoload に "AudioManager" という名前で登録する）
## BGM の切り替え（フェード付き）と SE の再生をまとめて扱う
extends Node

## 使うオーディオバス。存在しなければ Master を使う
const BGM_BUS := &"BGM"
const SE_BUS := &"SE"
## フェードの長さ（秒）
const FADE_TIME := 0.5
const SILENT_DB := -40.0

## いま鳴らしている（または鳴らす予定の）BGM。null なら無音
var current_bgm: AudioStream = null

var _bgm: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	# ポーズ中でも音の切り替えが止まらないようにする
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = _bus_or_master(BGM_BUS)
	add_child(_bgm)


## 現在の BGM の再生位置（秒）
func get_bgm_position() -> float:
	return _bgm.get_playback_position() if _bgm.playing else 0.0


## BGM を切り替える。stream が null なら止める。同じ曲が鳴っていれば何もしない
func play_bgm(stream: AudioStream, from_position: float = 0.0, fade: float = FADE_TIME) -> void:
	if stream == current_bgm and (_bgm.playing or stream == null):
		return
	current_bgm = stream

	if _tween:
		_tween.kill()
	_tween = create_tween()
	var use_fade := fade > 0.0
	# 鳴っている曲をフェードアウト
	if _bgm.playing and use_fade:
		_tween.tween_property(_bgm, "volume_db", SILENT_DB, fade)
	# 曲を差し替える
	_tween.tween_callback(_start_bgm.bind(stream, from_position, use_fade))
	# 新しい曲をフェードイン
	if stream and use_fade:
		_tween.tween_property(_bgm, "volume_db", 0.0, fade)


func stop_bgm(fade: float = FADE_TIME) -> void:
	play_bgm(null, 0.0, fade)


## JSON などからパスで指定するとき用
func play_bgm_path(path: String, from_position: float = 0.0) -> void:
	play_bgm(_load_stream(path), from_position)


## SE を鳴らす。複数同時に鳴らせる
func play_se(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _bus_or_master(SE_BUS)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_se_path(path: String) -> void:
	play_se(_load_stream(path))


func _start_bgm(stream: AudioStream, from_position: float, use_fade: bool) -> void:
	_bgm.stop()
	if stream == null:
		return
	_bgm.stream = stream
	_bgm.volume_db = SILENT_DB if use_fade else 0.0
	_bgm.play(from_position)


func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: ファイルが見つかりません: " + path)
		return null
	return load(path) as AudioStream


func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) != -1 else &"Master"
