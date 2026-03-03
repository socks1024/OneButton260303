class_name GhostSpawner
extends Node
## 鬼怪生成管理器。
## 采用波次式随机生成：安全期 → 鬼怪活跃期 → 循环。
## 随玩家奔跑距离推进，鬼怪生成频率增加、数量增加、存在时间变长、
## 生成位置靠近玩家、玩家掉 San 速率上升。

## 需要由外部注入的玩家引用
var player: Player
## 需要由外部注入的父节点（鬼添加到哪个节点下）
var spawn_parent: Node3D

## 当前存活的鬼列表（供 Player 读取）
var active_ghosts: Array[Ghost] = []

## 当前距离对应的恐惧增长倍率（供 Player 读取）
var fear_gain_multiplier := 1.0

## --- 生成参数（基础值，会随距离动态调整） ---
## 安全期基础时长（秒）
@export var base_safe_duration := 6.0
## 活跃期基础时长（秒）
@export var base_active_duration := 4.0
## 活跃期内生成间隔基础值（秒）
@export var base_spawn_interval := 2.0
## 每次生成的基础鬼怪数量
@export var base_spawn_count := 1
## 鬼怪基础存在时间（秒）
@export var base_ghost_lifetime := 4.0
## 鬼怪生成距玩家的基础Z偏移（负值=玩家前方）
@export var base_spawn_distance := 30.0
## 鬼怪生成距玩家的最近Z偏移
@export var min_spawn_distance := 8.0
## 鬼怪生成的X轴基础范围（初始较大=鬼在路边远处，逐渐缩小=靠近路中央）
@export var base_spawn_x_range := 4.0
## 鬼怪生成的X轴最小范围（难度最高时，鬼就在路中央附近）
@export var min_spawn_x_range := 0.5
## 鬼怪生成的Y轴范围（高度偏移范围）
@export var spawn_y_min := 0.5
@export var spawn_y_max := 2.0

## --- 难度缩放参数 ---
## 通用难度参考距离（跑这么远时通用难度因子=1.0，影响生成频率、数量、存在时间、安全/活跃期时长）
@export var difficulty_scale_distance := 300.0
## 鬼颜色变红的参考距离（跑这么远时鬼完全变红，恐惧增长倍率达到最大）
@export var color_max_distance := 500.0
## 鬼生成位置靠近的参考距离（跑这么远时鬼贴到最近距离）
@export var proximity_max_distance := 500.0

## --- 数量增长参数 ---
## 数量增长系数（越大数量上涨越快）
@export var spawn_count_growth := 1.5
## 最大额外生成数量（在基础数量上最多额外增加几只）
@export var max_extra_spawn_count := 2

## --- 生成间隔缩短参数 ---
## 间隔缩短系数（越大间隔缩短越快）
@export var interval_shrink_rate := 0.6
## 间隔最低比例（基础间隔的最低百分比，0.4 = 最短为基础值的40%）
@export var interval_min_ratio := 0.4

## --- 安全期/活跃期参数 ---
## 安全期缩短系数（越大安全期缩短越快）
@export var safe_shrink_rate := 0.7
## 安全期最低比例（基础安全期的最低百分比）
@export var safe_min_ratio := 0.3
## 活跃期延长系数（越大活跃期延长越快）
@export var active_growth_rate := 1.5
## 活跃期最高倍率上限
@export var active_max_multiplier := 2.5

## --- 鬼存在时间参数 ---
## 存在时间延长系数（越大存在时间增长越快）
@export var lifetime_growth_rate := 1.5
## 存在时间最高倍率上限
@export var lifetime_max_multiplier := 2.5

## --- 恐惧倍率参数 ---
## 恐惧增长倍率的最大额外值（最终倍率 = 1.0 + 此值）
@export var fear_max_extra := 2.0

## 内部状态
enum Phase { SAFE, ACTIVE }
var _current_phase := Phase.SAFE
## 当前阶段剩余时间
var _phase_timer := 0.0
## 活跃期内距下次生成的计时
var _spawn_timer := 0.0
## 是否启用
var _enabled := false


func _ready() -> void:
	# 初始进入安全期
	_enter_safe_phase()
	_enabled = true


func _process(delta: float) -> void:
	if not _enabled or player == null:
		return

	# 更新难度倍率
	_update_difficulty()

	# 阶段计时
	_phase_timer -= delta

	match _current_phase:
		Phase.SAFE:
			if _phase_timer <= 0.0:
				_enter_active_phase()
		Phase.ACTIVE:
			if _phase_timer <= 0.0:
				_enter_safe_phase()
			else:
				# 活跃期内按间隔生成鬼
				_spawn_timer -= delta
				if _spawn_timer <= 0.0:
					_do_spawn()
					_spawn_timer = _get_spawn_interval()


## 进入安全期（无鬼）
func _enter_safe_phase() -> void:
	_current_phase = Phase.SAFE
	var difficulty := _get_difficulty_factor()
	# 安全期随难度缩短
	_phase_timer = base_safe_duration * maxf(1.0 - difficulty * safe_shrink_rate, safe_min_ratio)


## 进入活跃期（生成鬼）
func _enter_active_phase() -> void:
	_current_phase = Phase.ACTIVE
	var difficulty := _get_difficulty_factor()
	# 活跃期随难度延长
	_phase_timer = base_active_duration * minf(1.0 + difficulty * active_growth_rate, active_max_multiplier)
	_spawn_timer = 0.0  # 立刻生成第一波


## 更新距离相关的难度参数
func _update_difficulty() -> void:
	var distance := player.get_distance_traveled()
	# 颜色/恐惧倍率：使用 color_max_distance 独立控制
	var color_factor := clampf(distance / color_max_distance, 0.0, 1.0)
	fear_gain_multiplier = 1.0 + color_factor * fear_max_extra
	# 更新所有存活鬼的威胁强度（用于颜色渐变：蓝→红）
	var threat := color_factor
	for ghost in active_ghosts:
		if is_instance_valid(ghost):
			ghost.threat_intensity = threat


## 获取当前难度因子（0.0 ~ 1.0+，距离越远越高）
func _get_difficulty_factor() -> float:
	if player == null:
		return 0.0
	return player.get_distance_traveled() / difficulty_scale_distance


## 获取当前生成间隔（随难度缩短）
func _get_spawn_interval() -> float:
	var difficulty := _get_difficulty_factor()
	# 间隔缩短
	return base_spawn_interval * maxf(1.0 - difficulty * interval_shrink_rate, interval_min_ratio)


## 获取当前单次生成数量（随难度增加）
func _get_spawn_count() -> int:
	var difficulty := _get_difficulty_factor()
	# 数量增加
	return mini(base_spawn_count + int(difficulty * spawn_count_growth), base_spawn_count + max_extra_spawn_count)


## 获取当前鬼的存在时间（随难度增加）
func _get_ghost_lifetime() -> float:
	var difficulty := _get_difficulty_factor()
	# 存在时间延长
	return base_ghost_lifetime * minf(1.0 + difficulty * lifetime_growth_rate, lifetime_max_multiplier)


## 获取当前鬼生成距离（使用 proximity_max_distance 独立控制靠近速度）
func _get_spawn_z_offset() -> float:
	var distance := player.get_distance_traveled()
	var proximity_factor := clampf(distance / proximity_max_distance, 0.0, 1.0)
	# 从 base_spawn_distance 线性靠近到 min_spawn_distance
	return lerpf(base_spawn_distance, min_spawn_distance, proximity_factor)


## 获取当前鬼生成的X轴范围（与靠近速度同步，鬼从路边远处逐渐靠近路中央）
func _get_spawn_x_range() -> float:
	var distance := player.get_distance_traveled()
	var proximity_factor := clampf(distance / proximity_max_distance, 0.0, 1.0)
	return lerpf(base_spawn_x_range, min_spawn_x_range, proximity_factor)


## 执行一次鬼生成
func _do_spawn() -> void:
	if player == null or spawn_parent == null:
		return

	var count := _get_spawn_count()
	var lifetime := _get_ghost_lifetime()
	var z_offset := _get_spawn_z_offset()

	for i in count:
		var ghost := Ghost.new()
		ghost.lifetime = lifetime

		# 随机位置：在玩家前方 z_offset 处，X 和 Y 随机偏移
		# X 轴范围随难度缩小，鬼从路两侧远处逐渐靠近路中央（靠近玩家）
		var x_range := _get_spawn_x_range()
		var x_offset := randf_range(-x_range, x_range)
		var y_offset := randf_range(spawn_y_min, spawn_y_max)
		# Z 偏移加一点随机散布（±20%），避免所有鬼在同一直线上
		var z_jitter := z_offset * randf_range(0.8, 1.2)

		var spawn_pos := player.global_position + Vector3(x_offset, y_offset, -z_jitter)
		ghost.global_position = spawn_pos

		# 连接消失信号，从列表中移除
		ghost.ghost_vanished.connect(_on_ghost_vanished)

		spawn_parent.add_child(ghost)
		active_ghosts.append(ghost)


## 鬼消失时的回调
func _on_ghost_vanished(ghost: Ghost) -> void:
	active_ghosts.erase(ghost)


## 停止生成（游戏结束时调用）
func stop() -> void:
	_enabled = false
