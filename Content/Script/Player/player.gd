class_name Player
extends CharacterBody3D
## 玩家角色，自动沿Z轴负方向奔跑。
## 使用 CharacterBody3D 配合 move_and_slide 实现移动和重力。

## 玩家掉落信号（掉入断口时触发）
signal player_fell
## 闭眼状态变化信号（is_closed: bool）
signal eyes_state_changed(is_closed: bool)
## 恐惧值满信号（被吓死）
signal fear_maxed
## 迷失值满信号（永远迷失）
signal lost_maxed

## 初始移动速度
@export var base_speed := 8.0
## 重力
@export var gravity := 20.0
## 掉落判定的Y坐标阈值
@export var fall_threshold := -10.0
## 跳跃高度（米），决定每次跳跃的最高点，所有跳跃高度一致
@export var jump_height := 1.5
## 跳跃安全裕量（落点距断口对面边缘多远，单位：米）
## 值越大落点越靠近对面安全区中间，值越小越擦边
@export var jump_landing_margin := 1.0
## 前方地面探测距离（距玩家脚下前方多远开始探测）
@export var gap_detect_distance := 2.0
## 跳跃后的冷却时间（落地后多久才能再次起跳）
@export var jump_cooldown := 0.3

## 难度配置资源引用（由 GameWorld 注入）
var difficulty_config: DifficultyConfig

## 当前移动速度
var current_speed := 0.0
## 存活时间
var alive_time := 0.0
## 是否已掉落
var has_fallen := false
## 是否正在运行
var is_running := true
## 是否正处于闭眼状态（按住空格=闭眼，松开=睁眼）
var is_eyes_closed := false
## 玩家数值管理（San值 + 勇气值）
var stats: PlayerStats
## 跳跃冷却计时器（> 0 时不允许再次自动跳跃）
var _jump_cooldown_timer := 0.0
## 上一帧是否在地面上（用于检测刚落地的时刻）
var _was_on_floor := true
## 跳跃时锁定的水平速度（跳跃期间保持不变，落地后清除）
var _jump_locked_speed := 0.0
## 是否正在跳跃中（用于锁定水平速度）
var _is_jumping := false

## RoadManager 引用（由 game_world 注入，用于查询断口信息）
var road_manager: RoadManager
## 鬼怪生成器引用（由 game_world 注入）
var ghost_spawner: GhostSpawner
## 相机节点引用（在场景中通过路径设置）
var _camera: Camera3D
## 前方地面探测射线
var _ground_ray: RayCast3D


func _ready() -> void:
	current_speed = base_speed
	# 查找子节点中的相机
	_camera = _find_camera()
	# 创建前方地面探测射线
	_setup_ground_ray()
	# 初始化数值系统
	_setup_stats()


func _physics_process(delta: float) -> void:
	if not is_running:
		return

	# 更新存活时间和速度
	alive_time += delta
	var dist := get_distance_traveled()
	current_speed = difficulty_config.sample_param("speed", dist)

	# 动态更新数值参数（从难度配置读取，允许随阶段变化）
	stats.fear_gain_rate = difficulty_config.sample_param("fear_gain_rate", dist)
	stats.fear_decay_rate = difficulty_config.sample_param("fear_decay_rate", dist)
	stats.lost_gain_rate = difficulty_config.sample_param("lost_gain_rate", dist)
	stats.lost_decay_rate = difficulty_config.sample_param("lost_decay_rate", dist)

	# 数值消耗与恢复逻辑：判断当前鬼是否在玩家前方且已完全显现
	var ghost_visible := false
	if ghost_spawner and ghost_spawner.current_ghost:
		var ghost := ghost_spawner.current_ghost
		if is_instance_valid(ghost) and ghost.is_fully_visible:
			# 鬼必须在玩家前方（Z 比玩家小）
			if ghost.global_position.z < global_position.z:
				ghost_visible = true

	if is_eyes_closed:
		# 闭眼：迷失值增长，恐惧值下降
		stats.gain_lost(delta)
		stats.decay_fear(delta)
	else:
		# 睁眼：迷失值始终下降
		stats.decay_lost(delta)
		if ghost_visible:
			# 睁眼且有鬼：恐惧值增长
			stats.gain_fear(delta)
		else:
			# 睁眼且无鬼：恐惧值也下降
			stats.decay_fear(delta)

	# 更新跳跃冷却计时器
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer -= delta

	# 检测刚落地的时刻，开始冷却
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		# 刚落地，启动跳跃冷却，解除跳跃锁定
		_jump_cooldown_timer = jump_cooldown
		_is_jumping = false
		_jump_locked_speed = 0.0
	_was_on_floor = on_floor_now

	# 自动跳跃检测：在地面上且睁眼时，冷却结束后，检测前方是否有断口
	if on_floor_now and not is_eyes_closed and _jump_cooldown_timer <= 0.0:
		if not _ground_ray.is_colliding():
			# 前方地面消失（断口），自动跳跃
			# 垂直方向：固定高度 → 固定初速度
			velocity.y = _calculate_jump_velocity()
			# 水平方向：计算确保能飞过断口的最低速度，取 max(当前速度, 所需速度)
			_jump_locked_speed = _calculate_jump_horizontal_speed()
			_is_jumping = true

	# 闭眼时掉入断口检测：闭眼且在地面上时，检查玩家脚下是否处于断口区域
	# 如果脚下正好在断口上方，给一个向下的速度让玩家掉落（而不是滑过断口）
	if is_eyes_closed and on_floor_now and not _is_jumping:
		if _is_player_over_gap():
			# 玩家闭眼走到断口上方，施加向下速度使其掉落
			velocity.y = -gravity * delta
			on_floor_now = false

	# 应用重力
	if not on_floor_now:
		velocity.y -= gravity * delta
	else:
		# 只有没跳跃时才清零（避免覆盖刚设置的跳跃速度）
		if velocity.y < 0:
			velocity.y = 0.0

	# 自动向前移动（Z轴负方向）
	# 跳跃期间使用锁定的水平速度（保证飞过断口），落地后恢复正常速度
	if _is_jumping:
		velocity.z = -_jump_locked_speed
	else:
		velocity.z = -current_speed

	move_and_slide()

	# 掉落检测
	if position.y < fall_threshold and not has_fallen:
		has_fallen = true
		is_running = false
		player_fell.emit()
		CLog.w("玩家掉入了断口！")


func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return
	# 按住空格 = 闭眼，松开空格 = 睁眼
	if event.is_action_pressed("close_eye"):
		_set_eyes_closed(true)
	elif event.is_action_released("close_eye"):
		_set_eyes_closed(false)


## 设置闭眼/睁眼状态
func _set_eyes_closed(closed: bool) -> void:
	if is_eyes_closed == closed:
		return
	is_eyes_closed = closed
	eyes_state_changed.emit(closed)
	if closed:
		CLog.o("玩家闭上了眼睛")
	else:
		CLog.o("玩家睁开了眼睛")


## 获取玩家已经跑的距离（沿Z轴负方向）
func get_distance_traveled() -> float:
	return absf(position.z)


## 递归查找子节点中的 Camera3D
func _find_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	return null


## 初始化数值系统
func _setup_stats() -> void:
	stats = PlayerStats.new()
	stats.fear_maxed.connect(func(): fear_maxed.emit())
	stats.lost_maxed.connect(func(): lost_maxed.emit())


## 创建前方地面探测射线
func _setup_ground_ray() -> void:
	_ground_ray = RayCast3D.new()
	add_child(_ground_ray)
	# 射线起点在玩家前方（Z轴负方向），略高于地面
	_ground_ray.position = Vector3(0, 0.2, -gap_detect_distance)
	# 射线向下探测
	_ground_ray.target_position = Vector3(0, -2.0, 0)
	_ground_ray.enabled = true


## 根据固定跳跃高度计算跳跃垂直初速度
## 物理公式：v² = 2 * g * h → vy = sqrt(2 * gravity * jump_height)
## 无论玩家速度快慢，跳跃高度始终一致
func _calculate_jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)


## 根据断口信息计算跳跃所需的水平速度
## 保证玩家一定能飞过断口（睁眼状态下）
## 如果当前速度已经足够，直接使用当前速度
func _calculate_jump_horizontal_speed() -> float:
	# 计算固定跳跃高度对应的滞空时间
	# vy = sqrt(2*g*h), 滞空时间 t = 2*vy/g
	var vy := sqrt(2.0 * gravity * jump_height)
	var air_time := 2.0 * vy / gravity

	# 获取断口信息，计算需要飞过的水平距离
	var target_distance := RoadSegment.BASE_GAP_LENGTH + gap_detect_distance + jump_landing_margin
	if road_manager:
		var gap_info := road_manager.get_next_gap_info(position.z)
		if gap_info["has_gap"]:
			# 实际飞行距离 = 到断口的距离 + 断口长度 + 安全裕量
			target_distance = gap_info["distance_to_gap"] + gap_info["gap_length"] + jump_landing_margin

	# 所需最低水平速度 = 水平距离 / 滞空时间
	var required_speed := target_distance / air_time

	# 取当前速度和所需速度的较大值（速度够就不额外加速）
	return maxf(current_speed, required_speed)


## 判断玩家当前位置是否在某个断口的上方
func _is_player_over_gap() -> bool:
	if not road_manager:
		return false
	return road_manager.is_over_gap(position.z)
