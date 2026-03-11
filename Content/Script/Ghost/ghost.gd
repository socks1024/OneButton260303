class_name Ghost
extends Node3D
## 鬼实体，跟随玩家移动，保持相对偏移。
## 鬼具有多种状态（Idle、Move），每个状态对应一个子节点，
## 进入该状态时显示对应节点并播放动画，隐藏其他状态节点。

## 鬼消失时发出的信号（传递自身引用，供 GhostSpawner 回收）
signal ghost_vanished(ghost: Ghost)

## 鬼的状态枚举
enum State { IDLE, MOVE }

## 存在时间（秒），到时间后自动消失（由 GhostSpawner 注入）
var lifetime := 5.0
## 上下浮动的幅度（米）
@export var bob_amplitude := 0.3
## 上下浮动的频率（Hz）
@export var bob_frequency := 1.5
## 淡入持续时间（秒）
@export var fade_in_duration := 0.6
## 淡出持续时间（秒）
@export var fade_duration := 0.8
## Move 状态下鬼的水平移动速度（米/秒）
@export var move_speed := 0.8
## 鬼出现时播放的音乐事件
@export var ghost_music: AudioEvent
## 音乐轨道名称（用于 AudioManager 的音乐轨道管理）
const GHOST_MUSIC_TRACK := &"GhostMusic"

## 跟随的玩家引用（由 GhostSpawner 注入）
var follow_target: Node3D
## 相对于玩家的偏移量（鬼始终保持这个偏移跟随玩家）
var offset := Vector3.ZERO
## 由 GhostSpawner 注入的初始状态（在 _ready 中应用）
var initial_state: State = State.IDLE
## Move 状态下的水平移动方向（+1 = 向右移动，-1 = 向左移动）
## 由 GhostSpawner 根据鬼的初始位置自动决定
var move_direction := 1.0

## 各状态节点引用（场景中预设的子节点，每个状态节点下包含 Head/LeftArm/RightArm/Body）
@onready var _idle_node: Node3D = $Idle
@onready var _move_node: Node3D = $Move

## 状态枚举到节点的映射
var _state_nodes: Dictionary = {}
## 当前状态
var _current_state: State = State.IDLE
## 当前活跃状态节点下的 Sprite3D 数组（用于淡入淡出等批量操作）
var _sprites: Array[Sprite3D] = []

## 内部计时器（用于浮动动画）
var _time := 0.0
## 剩余存在时间
var _remaining_life := 0.0
## 基准 Y 偏移（生成时记录，用于浮动动画的基准）
var _base_y_offset := 0.0
## 是否正在淡出
var _fading := false
## 是否已完全显现（淡入完成后为 true，供外部判断是否应增长恐惧）
var is_fully_visible := false


func _ready() -> void:
	_remaining_life = lifetime
	_base_y_offset = offset.y
	# 建立状态到节点的映射
	_state_nodes = {
		State.IDLE: _idle_node,
		State.MOVE: _move_node,
	}
	# 切换到由 GhostSpawner 注入的初始状态，收集精灵并隐藏其他状态节点
	_switch_state(initial_state)
	# 如果是 Move 状态且向左移动（move_direction < 0），翻转 Move 节点的精灵
	if initial_state == State.MOVE and move_direction < 0.0:
		_move_node.scale.x = -1.0
	# 初始完全透明，然后执行淡入动画
	for sprite in _sprites:
		sprite.modulate.a = 0.0
	_start_fade_in()


func _process(delta: float) -> void:
	_time += delta
	_remaining_life -= delta

	# Move 状态下累加水平偏移（鬼缓缓向屏幕另一侧移动）
	if _current_state == State.MOVE:
		offset.x += move_direction * move_speed * delta

	# 跟随玩家移动：基于玩家位置 + 相对偏移
	if follow_target and is_instance_valid(follow_target):
		var target_pos := follow_target.global_position + offset
		# 上下浮动动画叠加在 Y 偏移上
		target_pos.y = follow_target.global_position.y + _base_y_offset + sin(_time * bob_frequency * TAU) * bob_amplitude
		global_position = target_pos

	# 整体面向摄像机（手动 billboard），让所有图层作为整体一起旋转
	var camera := get_viewport().get_camera_3d()
	if camera:
		var cam_pos := camera.global_position
		# 只在水平面（XZ平面）上旋转朝向摄像机，不做俯仰
		var look_target := Vector3(cam_pos.x, global_position.y, cam_pos.z)
		if global_position.distance_squared_to(look_target) > 0.001:
			look_at(look_target, Vector3.UP)
			# look_at 使 -Z 朝向目标，但鬼的正面是 +Z，所以需要旋转 180°
			rotate_y(PI)

	# 检查是否该开始淡出
	if not _fading and _remaining_life <= fade_duration:
		_fading = true
		_start_fade_out()

	# 存在时间结束，自动消失
	if _remaining_life <= 0.0:
		_fade_out_music()
		ghost_vanished.emit(self)
		queue_free()


# ============================================================
#  状态切换
# ============================================================

## 切换到指定状态：显示对应状态节点，隐藏其他状态节点，并收集当前状态的精灵
func _switch_state(new_state: State) -> void:
	_current_state = new_state
	# 显示/隐藏状态节点
	for state: State in _state_nodes:
		var node: Node3D = _state_nodes[state]
		node.visible = (state == new_state)
	# 收集当前活跃状态节点下的所有 Sprite3D 子节点
	_sprites.clear()
	var active_node: Node3D = _state_nodes[new_state]
	for child in active_node.get_children():
		if child is Sprite3D:
			_sprites.append(child)


## 外部调用：切换鬼的状态（例如从 Idle 切换到 Move）
func change_state(new_state: State) -> void:
	if new_state == _current_state:
		return
	# 保留当前透明度，切换后应用到新状态的精灵上
	var current_alpha := 1.0
	if _sprites.size() > 0:
		current_alpha = _sprites[0].modulate.a
	_switch_state(new_state)
	# 将透明度同步到新状态的精灵
	for sprite in _sprites:
		sprite.modulate.a = current_alpha


# ============================================================
#  音乐与淡入淡出
# ============================================================

## 淡出鬼的音乐
func _fade_out_music() -> void:
	if ghost_music and AudioManager.music_track_players.has(GHOST_MUSIC_TRACK):
		var player := AudioManager.music_track_players[GHOST_MUSIC_TRACK]
		if player.is_playing():
			player.fade_out(fade_duration, func() -> void:
				player.stop_audio()
			)


## 开始淡入动画（鬼出现时从透明逐渐显现）
func _start_fade_in() -> void:
	is_fully_visible = false
	var tween := create_tween()
	tween.set_parallel(true)
	for sprite in _sprites:
		tween.tween_property(sprite, "modulate:a", 1.0, fade_in_duration)
	# 淡入完成后标记为完全显现
	tween.chain().tween_callback(func(): is_fully_visible = true)
	# 淡入音乐
	if ghost_music:
		AudioManager.play_music(ghost_music, GHOST_MUSIC_TRACK, fade_in_duration)


## 开始淡出动画（鬼消失时逐渐变透明）
func _start_fade_out() -> void:
	is_fully_visible = false
	var tween := create_tween()
	tween.set_parallel(true)
	# 所有图层同时淡出
	for sprite in _sprites:
		tween.tween_property(sprite, "modulate:a", 0.0, fade_duration)
	# 淡出音乐
	_fade_out_music()
