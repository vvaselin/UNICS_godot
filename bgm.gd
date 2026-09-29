extends Node
## シーンの BGM を AudioManager で流す
@export var bgm: AudioStream

func _ready() -> void:
	AudioManager.play_bgm(bgm, 0.0, 0.0)  # フェードなしですぐ鳴らす
