class_name Ghost
extends Node3D
## 鬼实体，在固定世界坐标处存在一段时间后自动消失。
## 用半透明发光球体表示，带有上下浮动的动画效果。

## 鬼消失时发出的信号（传递自身引用，供 GhostSpawner 回收）
signal ghost_vanished(ghost: Ghost)

## 存在时间（秒），到时间后自动消失
@export var lifetime := 5.0
## 上下浮动的幅度（米）
@export var bob_amplitude := 0.3
## 上下浮动的频率（Hz）
@export var bob_frequency := 1.5
## 球体半径
@export var sphere_radius := 0.4
## 初始发光颜色（冰蓝色）
@export var glow_color := Color(0.6, 0.8, 1.0, 0.5)
## 危险时的发光颜色（红色）
@export var danger_color := Color(1.0, 0.2, 0.1, 0.7)
## 发光强度
@export var glow_energy := 2.0
## 淡出持续时间（秒）
@export var fade_duration := 0.8

## 当前威胁强度（0.0=安全蓝, 1.0=危险红），由 GhostSpawner 外部设置
var threat_intensity := 0.0

## 内部计时器（用于浮动动画）
var _time := 0.0
## 剩余存在时间
var _remaining_life := 0.0
## 基准 Y 坐标（生成时记录，用于浮动动画的基准）
var _base_y := 0.0
## 是否正在淡出
var _fading := false
## 当前混合后的颜色（缓存，用于淡出时的起始值）
var _current_color := Color.WHITE
## 球体网格实例
var _mesh_instance: MeshInstance3D
## 材质引用（用于淡出效果）
var _material: StandardMaterial3D
## 点光源（营造鬼火氛围）
var _light: OmniLight3D


func _ready() -> void:
	_remaining_life = lifetime
	_base_y = global_position.y
	_build_visual()


func _process(delta: float) -> void:
	_time += delta
	_remaining_life -= delta

	# 上下浮动动画
	global_position.y = _base_y + sin(_time * bob_frequency * TAU) * bob_amplitude

	# 根据威胁强度更新颜色（淡出中不再更新，避免冲突）
	if not _fading and _material:
		_update_color_by_threat()

	# 检查是否该开始淡出
	if not _fading and _remaining_life <= fade_duration:
		_fading = true
		_start_fade_out()

	# 存在时间结束，自动消失
	if _remaining_life <= 0.0:
		ghost_vanished.emit(self)
		queue_free()


## 构建鬼的视觉表现（半透明发光球体 + 点光源）
func _build_visual() -> void:
	# 半透明球体
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = sphere_radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_mesh_instance.mesh = sphere
	add_child(_mesh_instance)

	# 半透明发光材质
	_material = StandardMaterial3D.new()
	_material.albedo_color = glow_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color(glow_color.r, glow_color.g, glow_color.b)
	_material.emission_energy_multiplier = glow_energy
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = _material

	# 点光源 — 鬼火效果
	_light = OmniLight3D.new()
	_light.light_color = Color(glow_color.r, glow_color.g, glow_color.b)
	_light.light_energy = 0.8
	_light.omni_range = 3.0
	_light.omni_attenuation = 1.5
	add_child(_light)


## 根据威胁强度更新发光颜色（蓝 → 红渐变）
func _update_color_by_threat() -> void:
	var t := clampf(threat_intensity, 0.0, 1.0)
	# 在初始冰蓝色和危险红色之间插值
	_current_color = glow_color.lerp(danger_color, t)
	_material.albedo_color = _current_color
	var emission := Color(_current_color.r, _current_color.g, _current_color.b)
	_material.emission = emission
	# 威胁越高，发光越强
	_material.emission_energy_multiplier = lerpf(glow_energy, glow_energy * 1.8, t)
	# 光源颜色同步
	_light.light_color = emission
	_light.light_energy = lerpf(0.8, 1.5, t)


## 开始淡出动画
func _start_fade_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# 材质透明度渐变到 0
	tween.tween_property(_material, "albedo_color:a", 0.0, fade_duration)
	# 光源亮度渐变到 0
	tween.tween_property(_light, "light_energy", 0.0, fade_duration)
