class_name CameraShake
extends Node
## 相机跑步抖动效果组件
## 优先通过 Phantom Camera 输出抖动；若插件链路不可用则回退到 Camera3D 偏移

## 抖动强度（整体幅度）
@export var shake_intensity: float = 0.02
## 抖动频率倍率（1.0 为正常跑步节奏）
@export var shake_frequency: float = 12.0
## 是否启用抖动
@export var enabled: bool = true:
	set(value):
		_enabled_internal = value
		if not _enabled_internal:
			_reset_shake()
	get:
		return _enabled_internal

## 是否优先向 PhantomCamera3D 发送抖动
@export var use_phantom_camera: bool = true
## 期望的最高跑步速度（用于把速度映射为抖动强度）
@export var max_expected_speed: float = 12.0
## 左右摆动占比（越大越“晃”）
@export_range(0.0, 1.0, 0.01) var side_sway_ratio: float = 0.4
## 脚步落地冲击占比（越大越有“踩地”感）
@export_range(0.0, 1.0, 0.01) var impact_ratio: float = 0.35

var _enabled_internal: bool = true
var _camera: Camera3D = null
var _player: Player = null
var _phantom_camera: Node = null

var _phase: float = 0.0
var _original_h_offset: float = 0.0
var _original_v_offset: float = 0.0
var _current_h_offset: float = 0.0
var _current_v_offset: float = 0.0


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		return

	_original_h_offset = _camera.h_offset
	_original_v_offset = _camera.v_offset
	_current_h_offset = _original_h_offset
	_current_v_offset = _original_v_offset

	var camera_owner: Node = _camera.get_parent()
	if camera_owner is Player:
		_player = camera_owner as Player

	_phantom_camera = _find_phantom_camera(camera_owner)
	_enabled_internal = enabled
	if not _enabled_internal:
		_reset_shake()


func _process(delta: float) -> void:
	if _camera == null:
		return

	if not _enabled_internal:
		_relax_to_original(delta)
		_emit_phantom_noise(0.0, 0.0, 0.0, 0.0)
		return

	var move_ratio: float = _get_move_ratio()
	if move_ratio <= 0.001:
		_relax_to_original(delta)
		_emit_phantom_noise(0.0, 0.0, 0.0, 0.0)
		return

	var cadence: float = lerpf(1.8, 3.0, move_ratio) * maxf(shake_frequency, 0.01)
	_phase += delta * cadence * TAU

	var amplitude: float = shake_intensity * move_ratio
	var side_wave: float = sin(_phase)
	var step_wave: float = absf(sin(_phase))
	var impact_wave: float = maxf(0.0, sin(_phase * 2.0))

	var target_h: float = _original_h_offset + side_wave * amplitude * side_sway_ratio
	var target_v: float = _original_v_offset - step_wave * amplitude * (1.0 - impact_ratio) - impact_wave * amplitude * impact_ratio

	var blend: float = clampf(delta * 20.0, 0.0, 1.0)
	_current_h_offset = lerpf(_current_h_offset, target_h, blend)
	_current_v_offset = lerpf(_current_v_offset, target_v, blend)

	_camera.h_offset = _current_h_offset
	_camera.v_offset = _current_v_offset

	var roll_rad: float = deg_to_rad(side_wave * amplitude * 4.0)
	var pitch_rad: float = deg_to_rad(-impact_wave * amplitude * 3.0)
	_emit_phantom_noise(_current_h_offset - _original_h_offset, _current_v_offset - _original_v_offset, pitch_rad, roll_rad)


func _get_move_ratio() -> float:
	if _player == null:
		return 1.0
	if not _player.is_running:
		return 0.0

	var speed: float = _player.current_speed
	var speed_ratio: float = speed / maxf(max_expected_speed, 0.001)
	return clampf(speed_ratio, 0.0, 1.0)


func _relax_to_original(delta: float) -> void:
	var blend: float = clampf(delta * 12.0, 0.0, 1.0)
	_current_h_offset = lerpf(_current_h_offset, _original_h_offset, blend)
	_current_v_offset = lerpf(_current_v_offset, _original_v_offset, blend)
	_camera.h_offset = _current_h_offset
	_camera.v_offset = _current_v_offset


func _reset_shake() -> void:
	_phase = 0.0
	if _camera != null:
		_current_h_offset = _original_h_offset
		_current_v_offset = _original_v_offset
		_camera.h_offset = _original_h_offset
		_camera.v_offset = _original_v_offset
	_emit_phantom_noise(0.0, 0.0, 0.0, 0.0)


func _find_phantom_camera(camera_owner: Node) -> Node:
	if camera_owner == null:
		return null

	var sibling: Node = camera_owner.get_node_or_null("PhantomCamera3D")
	if sibling != null:
		return sibling

	return camera_owner.find_child("PhantomCamera3D", true, false)


func _emit_phantom_noise(offset_x: float, offset_y: float, pitch_rad: float, roll_rad: float) -> void:
	if not use_phantom_camera:
		return
	if _phantom_camera == null:
		return
	if not is_instance_valid(_phantom_camera):
		return
	if not _phantom_camera.has_method("emit_noise"):
		return

	var rotation: Vector3 = Vector3(pitch_rad, 0.0, roll_rad)
	var position: Vector3 = Vector3(offset_x, offset_y, 0.0)
	var noise_transform: Transform3D = Transform3D(Quaternion.from_euler(rotation), position)
	_phantom_camera.call("emit_noise", noise_transform)
