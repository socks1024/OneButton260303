extends Control

## 每次点击的进度变化量
@export_range(0.01, 0.5) var step: float = 0.1

@onready var _progress_bar: FeelProgressBar = $CenterContainer/VBoxContainer/FeelProgressBar
@onready var _label: Label = $CenterContainer/VBoxContainer/Label
@onready var _btn_decrease: Button = $CenterContainer/VBoxContainer/HBoxContainer/BtnDecrease
@onready var _btn_increase: Button = $CenterContainer/VBoxContainer/HBoxContainer/BtnIncrease


func _ready() -> void:
	_btn_decrease.pressed.connect(_on_decrease)
	_btn_increase.pressed.connect(_on_increase)
	_update_label()


func _on_decrease() -> void:
	_progress_bar.value = _progress_bar.value - step
	_update_label()


func _on_increase() -> void:
	_progress_bar.value = _progress_bar.value + step
	_update_label()


func _update_label() -> void:
	_label.text = "当前进度：%.0f%%" % (_progress_bar.value * 100.0)
