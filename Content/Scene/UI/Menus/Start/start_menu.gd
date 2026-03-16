extends Control

@export var blink_speed: float = 1

@onready var bridge: TextureRect = $Panel/Bridge
@onready var title: TextureRect = $Panel/Title
@onready var play_button: TextureButton = $Panel/Play

## UI 点击音效
var _sfx_ui_click: AudioEvent = preload("res://Content/Art/Audio/Events/SFX/sfx_ui_click.tres")
## 悬浮时的变暗颜色
const HOVER_COLOR: Color = Color(0.7, 0.7, 0.7, 1.0)


func _ready() -> void:
	# 连接 Play 按钮信号
	play_button.mouse_entered.connect(_on_play_mouse_entered)
	play_button.mouse_exited.connect(_on_play_mouse_exited)
	play_button.pressed.connect(_on_play_pressed)


func _process(_delta: float) -> void:
	bridge.modulate.a = abs(sin(Time.get_ticks_msec() * 0.001 * blink_speed)) * 0.5 + 0.5


## Play 按钮鼠标悬浮 — 变暗
func _on_play_mouse_entered() -> void:
	play_button.modulate = HOVER_COLOR


## Play 按钮鼠标离开 — 恢复正常
func _on_play_mouse_exited() -> void:
	play_button.modulate = Color.WHITE


## Play 按钮按下 — 播放点击音效
func _on_play_pressed() -> void:
	AudioManager.play_sound(_sfx_ui_click)


func _on_exit_clicked() -> void:
	get_tree().quit()
