class_name RoadManager
extends Node3D
## 道路管理器，负责无限生成和回收路段。
## 路段沿Z轴负方向延伸（玩家也沿Z轴负方向移动）。

## 在玩家前方保持多少段路
@export var segments_ahead := 5
## 在玩家后方保留多少段路（超出的会被回收）
@export var segments_behind := 2
## 断口出现的概率（0~1）
@export_range(0.0, 1.0) var gap_chance := 0.3
## 最少连续几段路没有断口（开局保护）
@export var safe_segments := 3
## 断口长度随速度增长的系数（每1m/s额外增加多少米断口）
@export var gap_length_per_speed := 0.3
## 用于计算断口长度的基准速度（低于此速度使用最小断口）
@export var gap_base_speed := 8.0

## 当前所有活跃的路段
var _segments: Array[RoadSegment] = []
## 下一个路段应该放置的Z坐标
var _next_segment_z := 0.0
## 已经生成的路段总数
var _total_segments_spawned := 0
## 上一段路是否有断口（防止连续断口导致跳进下一个断口）
var _last_segment_had_gap := false
## 当前玩家速度（由外部更新，用于动态计算断口长度）
var current_player_speed := 8.0


func _ready() -> void:
	# 初始生成一批路段
	for i in range(segments_ahead + segments_behind):
		_spawn_segment()


## 根据玩家位置和速度更新路段（生成前方的、回收后方的）
func update_road(player_z: float, player_speed: float = 8.0) -> void:
	current_player_speed = player_speed
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
	var segment := RoadSegment.new()

	# 决定是否有断口
	# 规则：开局保护期内无断口；上一段有断口则这段强制无断口，防止连续断口
	var should_have_gap := false
	if _total_segments_spawned >= safe_segments and not _last_segment_had_gap:
		should_have_gap = randf() < gap_chance

	# 根据当前玩家速度动态计算断口长度
	var speed_excess := maxf(current_player_speed - gap_base_speed, 0.0)
	var dynamic_gap_length := RoadSegment.BASE_GAP_LENGTH + speed_excess * gap_length_per_speed

	segment.setup(should_have_gap, dynamic_gap_length)
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
