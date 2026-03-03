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
## 速度随时间增长的倍率（每秒增加的速度）
@export var speed_increase_per_second := 0.3
## 重力
@export var gravity := 20.0
## 掉落判定的Y坐标阈值
@export var fall_threshold := -10.0
## 跳跃安全裕量（落点距断口对面边缘多远，单位：米）
## 值越大落点越靠近断口对面安全区中间，值越小越擦边
@export var jump_landing_margin := 1.5
## 前方地面探测距离（距玩家脚下前方多远开始探测）
@export var gap_detect_distance := 2.0
## 跳跃后的冷却时间（落地后多久才能再次起跳）
@export var jump_cooldown := 0.3

## --- 数值参数 ---
## 恐惧值增长速率（点/秒，看到鬼时）
@export var fear_gain_rate := 10.0
## 恐惧值下降速率（点/秒，闭眼时下降）
@export var fear_decay_rate := 3.0
## 迷失值增长速率（点/秒，闭眼时）
@export var lost_gain_rate := 5.0
## 迷失值下降速率（点/秒，睁眼时下降）
@export var lost_decay_rate := 4.0

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
	current_speed = base_speed + speed_increase_per_second * alive_time

	# 数值消耗与恢复逻辑：只统计玩家前方且 X 轴足够近的鬼
	var visible_ghost_count := 0
	if ghost_spawner:
		# 获取当前鬼生成的X范围作为可见判定阈值（加一点余量）
		var visible_x_threshold := ghost_spawner.base_spawn_x_range + 2.0
		for ghost: Ghost in ghost_spawner.active_ghosts:
			# 鬼必须在玩家前方（Z 比玩家小）
			if ghost.global_position.z >= global_position.z:
				continue
			# 用 X 轴距离判断远近：X 轴偏移在生成范围内才算可见
			var x_dist := absf(ghost.global_position.x - global_position.x)
			if x_dist < visible_x_threshold:
				visible_ghost_count += 1

	if is_eyes_closed:
		# 闭眼：迷失值增长，恐惧值下降
		stats.gain_lost(delta)
		stats.decay_fear(delta)
	else:
		# 睁眼：迷失值始终下降
		stats.decay_lost(delta)
		if visible_ghost_count > 0:
			# 睁眼且有鬼：恐惧值增长，距离倍率由 GhostSpawner 提供
			var distance_multiplier := 1.0
			if ghost_spawner:
				distance_multiplier = ghost_spawner.fear_gain_multiplier
			stats.gain_fear(delta, float(visible_ghost_count) * distance_multiplier)
		else:
			# 睁眼且无鬼：恐惧值也下降
			stats.decay_fear(delta)

	# 更新跳跃冷却计时器
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer -= delta

	# 检测刚落地的时刻，开始冷却
	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor:
		# 刚落地，启动跳跃冷却
		_jump_cooldown_timer = jump_cooldown
	_was_on_floor = on_floor_now

	# 自动跳跃检测：在地面上且睁眼时，冷却结束后，检测前方是否有断口
	if on_floor_now and not is_eyes_closed and _jump_cooldown_timer <= 0.0:
		if not _ground_ray.is_colliding():
			# 前方地面消失（断口），自动跳跃
			# 用物理公式精确计算跳跃力：刚好飞过断口 + 安全裕量
			velocity.y = _calculate_jump_velocity()

	# 应用重力
	if not on_floor_now:
		velocity.y -= gravity * delta
	else:
		# 只有没跳跃时才清零（避免覆盖刚设置的跳跃速度）
		if velocity.y < 0:
			velocity.y = 0.0

	# 自动向前移动（Z轴负方向）
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
	if event.is_action_pressed("jump"):
		_set_eyes_closed(true)
	elif event.is_action_released("jump"):
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
	stats.fear_gain_rate = fear_gain_rate
	stats.fear_decay_rate = fear_decay_rate
	stats.lost_gain_rate = lost_gain_rate
	stats.lost_decay_rate = lost_decay_rate
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


## 根据前方断口长度精确计算跳跃力度
## 物理模型：抛物线运动
##   水平飞行距离 = current_speed × 滞空时间
##   滞空时间 = 2 × vy / gravity  （上升+下降回到同一高度）
##   所以: 目标距离 = current_speed × 2 × vy / gravity
##   反推: vy = (目标距离 × gravity) / (2 × current_speed)
func _calculate_jump_velocity() -> float:
	# 从 RoadManager 获取前方最近断口的实际信息
	var target_distance := RoadSegment.BASE_GAP_LENGTH + gap_detect_distance + jump_landing_margin
	if road_manager:
		var gap_info := road_manager.get_next_gap_info(position.z)
		if gap_info["has_gap"]:
			# 完整飞行距离 = 起跳点到断口起点的距离 + 断口长度 + 安全裕量
			# distance_to_gap 是从玩家当前位置到断口起始边缘的距离
			# 但玩家在检测到断口时已经处于断口前 gap_detect_distance 处
			# 所以实际飞行距离 ≈ distance_to_gap + gap_length + landing_margin
			target_distance = gap_info["distance_to_gap"] + gap_info["gap_length"] + jump_landing_margin

	# 用物理公式反推跳跃力: vy = (distance * gravity) / (2 * horizontal_speed)
	var vy := (target_distance * gravity) / (2.0 * current_speed)

	# 限制最小和最大跳跃力，避免异常值
	vy = clampf(vy, 3.0, 20.0)
	return vy
