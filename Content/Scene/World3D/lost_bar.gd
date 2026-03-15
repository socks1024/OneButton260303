extends Control

@onready var _bg_1: TextureRect = $bg1
@onready var _bg_2: TextureRect = $bg2
@onready var _petals: Array[TextureRect] = [$"0",$"1",$"2",$"3",$"4",$"5",$"6"]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func set_value(value: float) -> void:
	_bg_1.modulate.a = (value - 0.5) / 0.5
	_bg_2.modulate.a = value / 0.5
	for i in range(_petals.size()):
		_petals[i].modulate.a = clampf(1 + i - value * _petals.size(), 0.0, 1.0)
