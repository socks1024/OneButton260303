class_name RoadSegment
extends Node3D
## 道路段，代表一段路面。可以包含断口（gap）。
## 节点树结构由 road_segment.tscn 场景提供，脚本负责数据控制。

## 路段总长度（沿Z轴负方向延伸）
const SEGMENT_LENGTH := 20.0
## 路面宽度
const ROAD_WIDTH := 4.0
## 路面厚度
const ROAD_HEIGHT := 0.5
## 默认断口长度（最小值）
const BASE_GAP_LENGTH := 3.0

## 预加载桥面和栅栏美术资源
const BridgeScene := preload("res://Content/Art/Model/bridge/bridge.tscn")
const HandrailScene := preload("res://Content/Art/Model/handdrail/handdrail.tscn")

## 预加载断口怪物场景
const GapMonsterScene := preload("res://Content/Scene/World3D/Road/gap_monster.tscn")

## --- 以下参数由 RoadManager 传入 ---

## 是否有断口
var has_gap := false
## 实际断口长度（根据速度动态计算）
var gap_length := BASE_GAP_LENGTH
## 断口在路段中的起始位置（相对于路段起点的Z偏移，负值）
var gap_start_z := 0.0
## 是否启用路面与栏杆描边（由 RoadManager 传入）
var outline_enabled := true
## 路面与栏杆描边颜色（由 RoadManager 传入）
var outline_color := Color(0.0, 0.0, 0.0, 1.0)
## 路面与栏杆描边粗细（由 RoadManager 传入）
var outline_width := 0.03
## 怪物 Y 轴偏移（米），由 RoadManager 传入
var monster_y_offset: float = 0.0

## --- 场景节点引用 ---

## 前半段路面（无断口时为完整路面）
@onready var _road_body: StaticBody3D = $RoadBody
@onready var _road_collision: CollisionShape3D = $RoadBody/CollisionShape3D

## 后半段路面（仅断口时启用）
@onready var _back_body: StaticBody3D = $BackBody
@onready var _back_collision: CollisionShape3D = $BackBody/CollisionShape3D




## 获取断口在世界坐标系中的起始Z位置
func get_gap_world_start_z() -> float:
	return position.z + gap_start_z


## 获取断口在世界坐标系中的结束Z位置
func get_gap_world_end_z() -> float:
	return position.z + gap_start_z - gap_length


## 初始化路段
## p_has_gap: 是否有断口
## p_gap_length: 断口长度（默认使用 BASE_GAP_LENGTH）
## p_monster_height: 怪物显示高度（米）
func setup(p_has_gap: bool, p_gap_length: float = BASE_GAP_LENGTH, p_monster_y_offset: float = 0.0) -> void:
	has_gap = p_has_gap
	gap_length = clampf(p_gap_length, BASE_GAP_LENGTH, SEGMENT_LENGTH - 8.0)
	monster_y_offset = p_monster_y_offset
	if has_gap:
		# 断口位置在路段中间区域随机（留出前后边距）
		var margin := 4.0
		gap_start_z = -randf_range(margin, SEGMENT_LENGTH - margin - gap_length)


## 场景就绪后根据 setup 的数据配置节点
func _ready() -> void:
	# 将场景中共享的子资源复制为独立副本，防止多实例互相影响
	_road_collision.shape = _road_collision.shape.duplicate()
	_back_collision.shape = _back_collision.shape.duplicate()
	_build_road()


## 根据断口数据配置场景节点
func _build_road() -> void:
	if not has_gap:
		# 无断口 —— RoadBody 使用完整 20m，BackBody 保持隐藏
		_setup_road_piece(_road_body, _road_collision, Vector3.ZERO, SEGMENT_LENGTH)
		_back_body.visible = false
		_back_body.process_mode = Node.PROCESS_MODE_DISABLED
		# 放置完整桥面美术模型和栅栏
		_place_bridge_art(Vector3.ZERO, SEGMENT_LENGTH)
	else:
		# 有断口 —— 分成两段
		var front_length := absf(gap_start_z)

		# 断口前的部分
		if front_length > 0.01:
			_setup_road_piece(_road_body, _road_collision, Vector3.ZERO, front_length)
			_place_bridge_art(Vector3.ZERO, front_length)
		else:
			_road_body.visible = false
			_road_body.process_mode = Node.PROCESS_MODE_DISABLED

		# 断口后的部分
		var back_start_z := gap_start_z - gap_length
		var back_length := SEGMENT_LENGTH - front_length - gap_length
		if back_length > 0.01:
			_back_body.visible = true
			_back_body.process_mode = Node.PROCESS_MODE_INHERIT
			_setup_road_piece(_back_body, _back_collision, Vector3(0, 0, back_start_z), back_length)
			_place_bridge_art(Vector3(0, 0, back_start_z), back_length)
		else:
			_back_body.visible = false
			_back_body.process_mode = Node.PROCESS_MODE_DISABLED

		# 在断口中央放置怪物装饰
		_place_gap_monster()


## 单段栅栏模型的长度（米）
const HANDRAIL_LENGTH := 5.0

## 在指定位置放置桥面美术模型和两侧栅栏
## p_start_pos: 这段路面的起始位置（局部坐标）
## p_length: 这段路面的长度
func _place_bridge_art(p_start_pos: Vector3, p_length: float) -> void:
	# 计算缩放比例（模型标准长度假设为 SEGMENT_LENGTH=20m）
	var length_scale := p_length / SEGMENT_LENGTH

	# 放置桥面模型
	var bridge := BridgeScene.instantiate()
	bridge.scale = Vector3(1, 1, length_scale)
	bridge.position = p_start_pos
	add_child(bridge)

	# 用多个5m栅栏拼接覆盖整段路面长度
	_place_handrails(p_start_pos, p_length)


## 沿路段两侧拼接放置栅栏
func _place_handrails(p_start_pos: Vector3, p_length: float) -> void:
	# 计算需要多少段栅栏（向上取整，最后一段可能需要缩放）
	var count := ceili(p_length / HANDRAIL_LENGTH)
	var remaining := p_length

	for i in count:
		# 当前栅栏的Z偏移（沿Z负方向排列）
		var z_offset := -i * HANDRAIL_LENGTH
		# 最后一段可能不足5m，需要缩放
		var seg_length := minf(HANDRAIL_LENGTH, remaining)
		var seg_scale := seg_length / HANDRAIL_LENGTH
		remaining -= seg_length

		# 左侧栅栏（旋转180°使其朝-Z方向延伸）
		var rail_left := HandrailScene.instantiate()
		rail_left.scale = Vector3(1, 1, seg_scale)
		rail_left.rotation.y = PI
		rail_left.position = p_start_pos + Vector3(-ROAD_WIDTH / 2.0, 0, z_offset)
		add_child(rail_left)

		# 右侧栅栏（镜像翻转 + 旋转180°）
		var rail_right := HandrailScene.instantiate()
		rail_right.scale = Vector3(-1, 1, seg_scale)
		rail_right.rotation.y = PI
		rail_right.position = p_start_pos + Vector3(ROAD_WIDTH / 2.0, 0, z_offset)
		add_child(rail_right)


func _apply_outline_to_instance(_root: Node) -> void:
	return


func _apply_outline_to_mesh(_mesh_instance: MeshInstance3D) -> void:
	return


## 在断口中央放置怪物装饰（实例化 gap_monster.tscn）
func _place_gap_monster() -> void:
	# 断口中心的Z坐标
	var gap_center_z: float = gap_start_z - gap_length / 2.0
	var monster: GapMonster = GapMonsterScene.instantiate()
	# 从 SpriteFrames 获取第一帧贴图尺寸来计算 pixel_size
	var first_frame: Texture2D = monster.sprite_frames.get_frame_texture("default", 0)
	var tex_height: int = first_frame.get_height()
	var half_world_height: float = tex_height * monster.pixel_size / 2.0
	# 位置：断口中央，怪物底部与路面底部齐平，再加上 Y 轴偏移
	monster.position = Vector3(0, -ROAD_HEIGHT + half_world_height + monster_y_offset, gap_center_z)
	add_child(monster)



## 配置一段路面的碰撞体尺寸与位置
func _setup_road_piece(
	body: StaticBody3D,
	collision: CollisionShape3D,
	p_position: Vector3,
	p_length: float
) -> void:
	# 调整碰撞体尺寸
	var box_shape := collision.shape as BoxShape3D
	box_shape.size = Vector3(ROAD_WIDTH, ROAD_HEIGHT, p_length)
	# 碰撞体中心偏移：X居中，Y向下半个厚度，Z居中于该段
	collision.position = p_position + Vector3(0, -ROAD_HEIGHT / 2.0, -p_length / 2.0)
