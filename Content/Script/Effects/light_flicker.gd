class_name LightFlicker
extends Node
## 灯光闪烁效果组件
## 挂载在 OmniLight3D 节点上，模拟灯光随机闪烁

## 基础光强（闪烁会围绕此值波动）
@export var base_energy := 1.0
## 闪烁强度范围（光强会在 base_energy ± flicker_range 范围内波动）
@export var flicker_range := 0.3
## 闪烁速度（值越大闪烁越快）
@export var flicker_speed := 5.0
## 随机性（0 = 完全规律，1 = 完全随机）
@export var randomness := 0.5
## 是否启用闪烁
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled and _light:
			_light.light_energy = base_energy

var _light: OmniLight3D
var _time := 0.0
var _random_offset := 0.0


func _ready() -> void:
	_light = get_parent() as OmniLight3D
	_random_offset = randf() * 1000.0
	if _light and base_energy <= 0.0:
		base_energy = _light.light_energy


func _process(delta: float) -> void:
	if not enabled or not _light:
		return
	
	_time += delta
	
	var noise_val := _noise(_time * flicker_speed + _random_offset)
	var flicker := noise_val * flicker_range
	_light.light_energy = base_energy + flicker


func _noise(x: float) -> float:
	var i := floori(x)
	var f := x - i
	var a := _hash(i)
	var b := _hash(i + 1)
	var smooth := f * f * (3.0 - 2.0 * f)
	return lerp(a, b, smooth) * 2.0 - 1.0


func _hash(n: int) -> float:
	n = (n << 13) ^ n
	return (1.0 - ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 1073741824.0) * 0.5 + 0.5
