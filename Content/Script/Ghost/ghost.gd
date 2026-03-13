class_name Ghost
extends Node3D
## 鬼实体，跟随玩家移动，保持相对偏移。
## 鬼具有多种状态（Idle、Move），每个状态对应一个子节点，
## 进入该状态时显示对应节点并播放动画，隐藏其他状态节点。

## 鬼消失时发出的信号（传递自身引用，供 GhostSpawner 回收）
signal ghost_vanished(ghost: Ghost)

## 鬼的状态枚举
enum State { IDLE, MOVE }

## 鬼完全显示后的持续时间（秒），淡入和淡出时间不计入（由 GhostSpawner 注入）
var lifetime: float = 5.0
## 上下浮动的幅度（米）
@export var bob_amplitude: float = 0.3
## 上下浮动的频率（Hz）
@export var bob_frequency: float = 1.5
## 淡入持续时间（秒）
@export var fade_in_duration: float = 0.6
## 淡出持续时间（秒)
@export var fade_duration: float = 0.8
## Move 状态下鬼的水平移动速度（米/秒）
@export var move_speed: float = 0.8
## 鬼出现时播放的音乐事件
@export var ghost_music: AudioEvent
## 音乐轨道名称（用于 AudioManager 的音乐轨道管理）
const GHOST_MUSIC_TRACK: StringName = &"GhostMusic"

## 跟随的玩家引用（由 GhostSpawner 注入）
var follow_target: Node3D
## 相对于玩家的偏移量（鬼始终保持这个偏移跟随玩家）
var offset: Vector3 = Vector3.ZERO
## 由 GhostSpawner 注入的初始状态（在 _ready 中应用）
var initial_state: State = State.IDLE
## Move 状态下的水平移动方向（+1 = 向右移动，-1 = 向左移动）
## 由 GhostSpawner 根据鬼的初始位置自动决定
var move_direction: float = 1.0

## 各状态节点引用
@onready var _idle_node: Node3D = $Idle
@onready var _move_node: Node3D = $Move

## 状态枚举到节点的映射
var _state_nodes: Dictionary = {}
## 当前状态
var _current_state: State = State.IDLE
## 当前活跃状态节点下的 AnimatedSprite3D 数组（用于淡入淡出等批量操作）
var _animated_sprites: Array[AnimatedSprite3D] = []

## 内部计时器（用于浮动动画）
var _time: float = 0.0
## 基准 Y 偏移（生成时记录，用于浮动动画的基准）
var _base_y_offset: float = 0.0
## 是否正在淡出
var _fading: bool = false
## 是否已完全显现（淡入完成后为 true，供外部判断是否应增长恐惧）
var is_fully_visible: bool = false
## 鬼的生命周期阶段
enum LifePhase { FADING_IN, VISIBLE, FADING_OUT, FINISHED }
var _life_phase: LifePhase = LifePhase.FADING_IN

## 计时器节点（由场景静态配置）
@onready var _visible_timer_node: Timer = $VisibleTimer

## 淡入淡出插值动画
var _fade_tween: Tween = null


func _ready() -> void:
	_base_y_offset = offset.y
	set_process(true)
	_state_nodes = {
		State.IDLE: _idle_node,
		State.MOVE: _move_node,
	}
	_switch_state(initial_state)
	if initial_state == State.MOVE and move_direction < 0.0:
		for sprite: AnimatedSprite3D in _animated_sprites:
			sprite.flip_h = true
	for sprite: AnimatedSprite3D in _animated_sprites:
		sprite.modulate.a = 0.0
	_setup_timer_nodes()
	call_deferred("_start_fade_in")


func _setup_timer_nodes() -> void:
	_visible_timer_node.one_shot = true
	_visible_timer_node.wait_time = max(lifetime, 0.0)

	var on_visible_timeout: Callable = Callable(self, "_on_visible_timer_timeout")
	if not _visible_timer_node.timeout.is_connected(on_visible_timeout):
		_visible_timer_node.timeout.connect(on_visible_timeout)


func _process(delta: float) -> void:
	_time += delta

	if _current_state == State.MOVE:
		offset.x += move_direction * move_speed * delta

	if follow_target and is_instance_valid(follow_target):
		var target_pos: Vector3 = follow_target.global_position + offset
		target_pos.y = follow_target.global_position.y + _base_y_offset + sin(_time * bob_frequency * TAU) * bob_amplitude
		global_position = target_pos

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var cam_pos: Vector3 = camera.global_position
		var look_target: Vector3 = Vector3(cam_pos.x, global_position.y, cam_pos.z)
		if global_position.distance_squared_to(look_target) > 0.001:
			look_at(look_target, Vector3.UP)
			rotate_y(PI)


func _switch_state(new_state: State) -> void:
	_current_state = new_state
	for state: State in _state_nodes:
		var node: Node3D = _state_nodes[state] as Node3D
		node.visible = (state == new_state)
	_animated_sprites.clear()
	var active_node: Node3D = _state_nodes[new_state] as Node3D
	for child: Node in active_node.get_children():
		if child is AnimatedSprite3D:
			var sprite: AnimatedSprite3D = child as AnimatedSprite3D
			_animated_sprites.append(sprite)
			sprite.play()


func change_state(new_state: State) -> void:
	if new_state == _current_state:
		return
	var current_alpha: float = 1.0
	if _animated_sprites.size() > 0:
		current_alpha = _animated_sprites[0].modulate.a
	_switch_state(new_state)
	for sprite: AnimatedSprite3D in _animated_sprites:
		sprite.modulate.a = current_alpha


func _fade_out_music() -> void:
	if ghost_music and AudioManager.music_track_players.has(GHOST_MUSIC_TRACK):
		var player: AudioEventPlayer = AudioManager.music_track_players[GHOST_MUSIC_TRACK]
		if player.is_playing():
			player.fade_out(fade_duration, func() -> void:
				player.stop_audio()
			)


func _start_fade_in() -> void:
	is_fully_visible = false
	_fading = false
	_life_phase = LifePhase.FADING_IN
	_stop_all_timers()
	_kill_fade_tween()
	for sprite: AnimatedSprite3D in _animated_sprites:
		sprite.modulate.a = 0.0

	if fade_in_duration <= 0.0:
		for sprite: AnimatedSprite3D in _animated_sprites:
			sprite.modulate.a = 1.0
		_on_fade_in_finished()
		return

	_fade_tween = create_tween()
	for sprite: AnimatedSprite3D in _animated_sprites:
		_fade_tween.parallel().tween_property(sprite, "modulate:a", 1.0, fade_in_duration)
	_fade_tween.finished.connect(Callable(self, "_on_fade_in_finished"))


func _on_fade_in_finished() -> void:
	if _life_phase != LifePhase.FADING_IN:
		return
	_kill_fade_tween()
	for sprite: AnimatedSprite3D in _animated_sprites:
		sprite.modulate.a = 1.0
	is_fully_visible = true
	_life_phase = LifePhase.VISIBLE

	if ghost_music:
		AudioManager.play_music(ghost_music, GHOST_MUSIC_TRACK, 0.1)

	if lifetime <= 0.0:
		_start_fade_out()
		return
	_visible_timer_node.wait_time = lifetime
	_visible_timer_node.start()


func _on_visible_timer_timeout() -> void:
	if _life_phase != LifePhase.VISIBLE:
		return
	_start_fade_out()


func _start_fade_out() -> void:
	if _life_phase == LifePhase.FINISHED:
		return
	is_fully_visible = false
	_fading = true
	_life_phase = LifePhase.FADING_OUT
	_stop_all_timers()
	_kill_fade_tween()

	if fade_duration <= 0.0:
		for sprite: AnimatedSprite3D in _animated_sprites:
			sprite.modulate.a = 0.0
		_on_fade_out_finished()
		return

	_fade_tween = create_tween()
	for sprite: AnimatedSprite3D in _animated_sprites:
		_fade_tween.parallel().tween_property(sprite, "modulate:a", 0.0, fade_duration)
	_fade_tween.finished.connect(Callable(self, "_on_fade_out_finished"))


func _on_fade_out_finished() -> void:
	if _life_phase != LifePhase.FADING_OUT:
		return
	_kill_fade_tween()
	for sprite: AnimatedSprite3D in _animated_sprites:
		sprite.modulate.a = 0.0
	_finish_fade_out()


func _finish_fade_out() -> void:
	if _life_phase == LifePhase.FINISHED:
		return
	_life_phase = LifePhase.FINISHED
	_fade_out_music()
	ghost_vanished.emit(self)
	queue_free()


func _stop_all_timers() -> void:
	_visible_timer_node.stop()


func _kill_fade_tween() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null


func fade_out_and_free() -> void:
	if _life_phase == LifePhase.FADING_OUT or _life_phase == LifePhase.FINISHED:
		return
	_start_fade_out()
