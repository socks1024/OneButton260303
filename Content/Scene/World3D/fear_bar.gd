extends Control

@export var color_safe: Color = Color(0,1,0.2)
@export var color_warn: Color = Color(1,0.8,0)
@export var color_danger: Color = Color(1,0,0)

@onready var _bar: ColorRect = $Bar
@onready var _bar_size_x: float = _bar.size.x


func set_value(value: float) -> void:
	_bar.size.x = (1.0 - value) * _bar_size_x
	_bar.position.x = -0.5 * _bar.size.x
	var bar_color: Color = _calc_bar_color(value)
	_bar.color = bar_color
	# 同步颜色和尺寸到 shader
	var mat: ShaderMaterial = _bar.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("bar_color", bar_color)
		mat.set_shader_parameter("bar_size", Vector2(_bar.size.x, maxf(_bar.size.y, 1.0)))


## 根据比例计算颜色（值越高越危险：绿 → 黄 → 红）
func _calc_bar_color(ratio: float) -> Color:
	if ratio < 0.5:
		# 绿 → 黄（0.0 ~ 0.5）
		var t: float = ratio / 0.5
		return lerp(color_safe, color_warn, t)
	else:
		# 黄 → 红（0.5 ~ 1.0）
		var t: float = (ratio - 0.5) / 0.5
		return lerp(color_warn, color_danger, t)
