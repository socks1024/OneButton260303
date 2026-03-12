class_name CameraShake
extends Node
## 相机跑步抖动效果组件
## 挂载在 Camera3D 节点上，模拟跑步时的相机微微抖动

## 抖动强度（位置偏移的最大值）
@export var shake_intensity := 0.02
## 抖动频率（每秒抖动次数）
@export var shake_frequency := 12.0
## 是否启用抖动
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled and _camera:
			_camera.h_offset = _original_h_offset
			_camera.v_offset = _original_v_offset

var _camera: Camera3D
var _time := 0.0
var _original_h_offset := 0.0
var _original_v_offset := 0.0


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera:
		_original_h_offset = _camera.h_offset
		_original_v_offset = _camera.v_offset


func _process(delta: float) -> void:
	if not enabled or not _camera:
		return
	
	_time += delta
	
	var shake_x := sin(_time * shake_frequency * TAU) * shake_intensity
	var shake_y := cos(_time * shake_frequency * TAU * 0.7) * shake_intensity * 0.5
	
	_camera.h_offset = _original_h_offset + shake_x
	_camera.v_offset = _original_v_offset + shake_y
