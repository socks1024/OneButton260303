class_name RoadManager
extends Node3D
## 道路管理器，负责无限生成和回收路段。
## 路段沿Z轴负方向延伸（玩家也沿Z轴负方向移动）。

## 路段场景预加载
const RoadSegmentScene := preload("res://Content/Scene/World3D/Road/road_segment.tscn")

## 在玩家前方保持多少段路
@export var segments_ahead := 5
## 在玩家后方保留多少段路（超出的会被回收）
@export var segments_behind := 2

## 难度配置资源引用（由 GameWorld 注入）
var difficulty_config: DifficultyConfig
## 用于获取当前距离的玩家引用（由 GameWorld 注入）
var player: Player


## --- 断口怪物 ---
@export_group("断口怪物")
## 怪物相对父节点的 Y 轴偏移（米），正值向上
@export var monster_y_offset: float = 0.0

## --- 断口宽度 ---
@export_group("断口宽度")
## 断口宽度占跳跃最大飞行距离的比例（0~1）
## 值越大断口越宽越难跳，值为1.0时断口刚好等于跳跃极限距离
@export_range(0.1, 1.0, 0.01) var gap_width_ratio := 0.6






## 当前所有活跃的路段
var _segments: Array[RoadSegment] = []
## 下一个路段应该放置的Z坐标
var _next_segment_z := 0.0
## 已经生成的路段总数
var _total_segments_spawned := 0
## 上一段路是否有断口（防止连续断口导致跳进下一个断口）
var _last_segment_had_gap := false


## 初始化道路（需在 difficulty_config 和 player 注入后由外部调用）
func initialize() -> void:
	for i in range(segments_ahead + segments_behind):
		_spawn_segment()






## 根据玩家位置更新路段（生成前方的、回收后方的）
func update_road(player_z: float) -> void:
	# 生成前方路段
	while _next_segment_z > player_z - RoadSegment.SEGMENT_LENGTH * segments_ahead:
		_spawn_segment()

	# 回收远离玩家的后方路段
	while _segments.size() > 0:
		var oldest: RoadSegment = _segments[0]
		var segment_end_z := oldest.position.z - RoadSegment.SEGMENT_LENGTH
		# 如果这段路已经完全在玩家后方足够远
		if segment_end_z > player_z + RoadSegment.SEGMENT_LENGTH * segments_behind:
			_segments.pop_front()
			oldest.queue_free()
		else:
			break


## 生成一段新路
func _spawn_segment() -> void:
	var segment: RoadSegment = RoadSegmentScene.instantiate()

	# 决定是否有断口
	# 规则：开局保护期内无断口；上一段有断口则这段强制无断口，防止连续断口
	var should_have_gap := false
	if _total_segments_spawned >= difficulty_config.safe_segments and not _last_segment_had_gap:
		var dist := player.get_distance_traveled()
		var chance := difficulty_config.sample_param("gap_chance", dist)
		should_have_gap = randf() < chance

	# 根据玩家当前速度动态计算断口宽度
	var gap_len := _calculate_gap_length()
	segment.setup(should_have_gap, gap_len, monster_y_offset)
	segment.position = Vector3(0, 0, _next_segment_z)

	add_child(segment)
	_segments.append(segment)

	_last_segment_had_gap = should_have_gap
	_next_segment_z -= RoadSegment.SEGMENT_LENGTH
	_total_segments_spawned += 1


## 查询玩家前方最近的断口信息
## 返回字典：{ "has_gap": bool, "gap_length": float, "distance_to_gap": float }
## distance_to_gap 是从 player_z 到断口起始边缘的距离
func get_next_gap_info(player_z: float) -> Dictionary:
	var result := { "has_gap": false, "gap_length": 0.0, "distance_to_gap": 999.0 }
	for segment in _segments:
		if not segment.has_gap:
			continue
		var gap_start := segment.get_gap_world_start_z()
		# 断口在玩家前方（Z轴负方向，所以 gap_start < player_z）
		if gap_start < player_z:
			var dist := player_z - gap_start
			if dist < result["distance_to_gap"]:
				result["has_gap"] = true
				result["gap_length"] = segment.gap_length
				result["distance_to_gap"] = dist
	return result


## 判断指定的Z坐标是否处于某个断口的上方
## 用于闭眼掉落检测：玩家闭眼走到断口上方时应掉落
func is_over_gap(z: float) -> bool:
	for segment in _segments:
		if not segment.has_gap:
			continue
		var gap_start := segment.get_gap_world_start_z()
		var gap_end := segment.get_gap_world_end_z()
		# 断口范围：gap_end < z < gap_start（Z轴负方向，gap_end更小）
		if z < gap_start and z > gap_end:
			return true
	return false


## 根据玩家当前速度动态计算断口宽度
## 公式：断口宽度 = 玩家速度 × 跳跃滞空时间 × gap_width_ratio
## 滞空时间由玩家的 jump_height 和 gravity 决定
## 结果不低于 BASE_GAP_LENGTH，确保断口始终有最小宽度
func _calculate_gap_length() -> float:
	if player == null:
		return RoadSegment.BASE_GAP_LENGTH
	var vy := sqrt(2.0 * player.gravity * player.jump_height)
	var air_time := 2.0 * vy / player.gravity
	var max_jump_distance := player.current_speed * air_time
	var gap_len := max_jump_distance * gap_width_ratio
	return maxf(gap_len, RoadSegment.BASE_GAP_LENGTH)
