class_name GhostSpawner
extends Node
## 鬼怪生成管理器。
## 采用波次式生成：安全期 → 鬼怪活跃期 → 循环。
## 同时只存在一个鬼，鬼跟随玩家同步移动。
## 随玩家奔跑距离推进，鬼的位置逐渐靠近玩家、恐惧增长倍率上升。

## 需要由外部注入的玩家引用
var player: Player
## 需要由外部注入的父节点（鬼添加到哪个节点下）
var spawn_parent: Node3D

## 当前存活的鬼（供 Player 读取，同时只存在一个鬼，无鬼时为 null）
var current_ghost: Ghost = null

## 难度配置资源引用（由 GameWorld 注入）
var difficulty_config: DifficultyConfig



# ============================================================
#  导出参数
# ============================================================

@export_group("生成位置 - Z轴（前方距离）", "spawn_z_")
## 游戏开始时鬼距玩家的 Z 偏移（米）
@export var spawn_z_start := 30.0
## 难度最大时鬼距玩家的 Z 偏移（米）
@export var spawn_z_end := 8.0
## Z偏移从 start 过渡到 end 所需的路程（米）
@export var spawn_z_transition_distance := 500.0

@export_group("生成位置 - X轴（横向范围）", "spawn_x_")
## 游戏开始时鬼的横向随机范围（米，在桥外侧偏移基础上叠加）
@export var spawn_x_range_start := 4.0
## 难度最大时鬼的横向随机范围（米）
@export var spawn_x_range_end := 0.5
## X范围从 start 过渡到 end 所需的路程（米）
@export var spawn_x_transition_distance := 500.0
## 鬼离桥中央的最小横向距离（鬼只会生成在此距离之外）
@export var spawn_x_min_from_center := 2.5

@export_group("生成位置 - Y轴（高度）", "spawn_y_")
## 鬼生成的最低高度偏移（米）
@export var spawn_y_min := 0.5
## 鬼生成的最高高度偏移（米）
@export var spawn_y_max := 2.0

## 内部状态
enum Phase { SAFE, ACTIVE }
var _current_phase := Phase.SAFE
## 当前阶段剩余时间
var _phase_timer := 0.0
## 是否启用
var _enabled := false


## 初始化生成器（需在 difficulty_config 和 player 注入后由外部调用）
func initialize() -> void:
	_enter_safe_phase()
	_enabled = true


func _process(delta: float) -> void:
	if not _enabled or player == null:
		return

	# 阶段计时
	_phase_timer -= delta

	match _current_phase:
		Phase.SAFE:
			if _phase_timer <= 0.0:
				_enter_active_phase()
		Phase.ACTIVE:
			if _phase_timer <= 0.0:
				_enter_safe_phase()


## 获取玩家当前奔跑距离
func _get_distance() -> float:
	if player == null:
		return 0.0
	return player.get_distance_traveled()


## 进入安全期（无鬼）
func _enter_safe_phase() -> void:
	_current_phase = Phase.SAFE
	var dist := _get_distance()
	_phase_timer = difficulty_config.sample_param("safe_duration", dist)
	# 移除当前鬼
	_remove_current_ghost()


## 进入活跃期（生成一个鬼）
func _enter_active_phase() -> void:
	_current_phase = Phase.ACTIVE
	var dist := _get_distance()
	_phase_timer = difficulty_config.sample_param("active_duration", dist)
	# 生成鬼
	_spawn_ghost()


## 获取当前鬼生成距离
func _get_spawn_z_offset() -> float:
	var progress: float = clampf(_get_distance() / spawn_z_transition_distance, 0.0, 1.0)
	var raw_z_offset: float = lerpf(spawn_z_start, spawn_z_end, progress)
	return _cap_spawn_z_for_visibility(raw_z_offset)


## 获取当前鬼生成的X轴范围
func _get_spawn_x_range() -> float:
	var progress: float = clampf(_get_distance() / spawn_x_transition_distance, 0.0, 1.0)
	return lerpf(spawn_x_range_start, spawn_x_range_end, progress)


## 基于相机与雾效配置，限制鬼的前方生成距离，避免生成在不可见区域
func _cap_spawn_z_for_visibility(raw_z_offset: float) -> float:
	var capped: float = raw_z_offset

	# 1) 受相机远裁剪面约束
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		capped = minf(capped, camera.far * 0.75)

		# 2) 受全局雾深度约束（本项目世界中雾深度较近）
		var world_3d: World3D = camera.get_world_3d()
		if world_3d and world_3d.environment and world_3d.environment.fog_enabled:
			var fog_end: float = world_3d.environment.fog_depth_end
			if fog_end > 0.0:
				capped = minf(capped, fog_end * 0.8)

	# 保底：至少保证在玩家前方有一定距离，避免贴脸生成
	return maxf(capped, 2.0)


## 基于当前相机视角估算可见的横向范围（世界单位）
func _get_visible_half_width_at_distance(distance: float) -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return INF

	var viewport_size: Vector2i = get_viewport().get_visible_rect().size
	if viewport_size.y <= 0:
		return INF

	var aspect: float = float(viewport_size.x) / float(viewport_size.y)
	var half_vertical: float = tan(deg_to_rad(camera.fov) * 0.5) * distance
	return half_vertical * aspect


## 将“相机局部空间偏移”转换为世界偏移，确保鬼总是在当前镜头前方
func _build_world_offset_from_camera(local_x: float, local_y: float, local_forward: float) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		# 回退：没有相机时使用世界坐标系（与旧逻辑一致）
		return Vector3(local_x, local_y, -local_forward)

	var right: Vector3 = camera.global_transform.basis.x.normalized()
	var forward: Vector3 = -camera.global_transform.basis.z
	# 仅取水平前向，避免相机俯仰把鬼抬到天上或压到地面
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	else:
		forward = forward.normalized()

	return right * local_x + Vector3(0.0, local_y, 0.0) + forward * local_forward


## 随机生成一个偏移量（相对于玩家的位置）
## 鬼只会出现在桥面两侧的虚空中，不会在桥面上
func _random_offset() -> Vector3:
	var z_offset: float = _get_spawn_z_offset()
	# Z 偏移加一点随机散布（±20%）
	var z_jitter: float = z_offset * randf_range(0.8, 1.2)

	var x_range: float = _get_spawn_x_range()
	# X偏移：在桥面外生成，范围为 [min_from_center, min_from_center + x_range]
	var x_abs: float = spawn_x_min_from_center + randf_range(0.0, x_range)
	# 为了保证可见性，限制在相机视锥横向范围内（预留边距）
	var visible_half_width: float = _get_visible_half_width_at_distance(z_jitter)
	if visible_half_width < INF:
		x_abs = minf(x_abs, visible_half_width * 0.8)
		x_abs = maxf(x_abs, spawn_x_min_from_center)
	# 随机左右两侧
	if randf() < 0.5:
		x_abs = -x_abs

	var y_offset: float = randf_range(spawn_y_min, spawn_y_max)
	return _build_world_offset_from_camera(x_abs, y_offset, z_jitter)


## 鬼的场景资源（预加载）
const GHOST_SCENE := preload("res://Content/Scene/World3D/ghost.tscn")

## 生成一个鬼
func _spawn_ghost() -> void:
	if player == null or spawn_parent == null:
		return

	# 确保之前的鬼已清理
	_remove_current_ghost()

	var ghost: Ghost = GHOST_SCENE.instantiate()
	ghost.lifetime = _phase_timer  # 鬼的存在时间等于活跃期剩余时间
	ghost.follow_target = player
	ghost.offset = _random_offset()

	# 随机选择鬼的初始状态（Idle 或 Move）
	var random_state: Ghost.State
	if randf() < 0.5:
		random_state = Ghost.State.IDLE
	else:
		random_state = Ghost.State.MOVE
	ghost.initial_state = random_state

	# 如果是 Move 状态，根据鬼所在侧面决定移动方向
	# 精灵图默认朝向是从左至右，鬼应从屏幕外侧向内侧（桥的方向）移动
	# X > 0 在玩家右侧 → 向左移（-1），需要翻转精灵
	# X < 0 在玩家左侧 → 向右移（+1），使用默认朝向
	if random_state == Ghost.State.MOVE:
		ghost.move_direction = -1.0 if ghost.offset.x > 0.0 else 1.0

	# 连接消失信号（鬼自行消失时清理引用）
	ghost.ghost_vanished.connect(_on_ghost_vanished)

	# 先加入场景树，再设置 global_position
	# （未加入场景树的节点设置 global_position 无效，会导致鬼出现在原点）
	spawn_parent.add_child(ghost)
	ghost.global_position = player.global_position + ghost.offset
	current_ghost = ghost


## 移除当前的鬼（触发淡出效果）
func _remove_current_ghost() -> void:
	if current_ghost and is_instance_valid(current_ghost):
		current_ghost.ghost_vanished.disconnect(_on_ghost_vanished)
		# 触发淡出效果，让鬼自行消失
		current_ghost.fade_out_and_free()
		current_ghost = null


## 鬼自行消失时的回调（lifetime 耗尽触发）
func _on_ghost_vanished(ghost: Ghost) -> void:
	if ghost == current_ghost:
		current_ghost = null


## 停止生成（游戏结束时调用）
func stop() -> void:
	_enabled = false
	_remove_current_ghost()


## 是否当前有存活的鬼
func has_ghost() -> bool:
	return current_ghost != null and is_instance_valid(current_ghost)
