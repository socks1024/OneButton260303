class_name RoadSegment
extends Node3D
## 道路段，代表一段路面。可以包含断口（gap）。

## 路段总长度（沿Z轴负方向延伸）
const SEGMENT_LENGTH := 20.0
## 路面宽度
const ROAD_WIDTH := 4.0
## 路面厚度
const ROAD_HEIGHT := 0.5
## 默认断口长度（最小值）
const BASE_GAP_LENGTH := 3.0

## --- 以下参数可在编辑器中调整（通过 RoadManager 传入） ---

## 是否有断口
var has_gap := false
## 实际断口长度（根据速度动态计算）
var gap_length := BASE_GAP_LENGTH
## 断口在路段中的起始位置（相对于路段起点的Z偏移，负值）
var gap_start_z := 0.0


## 获取断口在世界坐标系中的起始Z位置
func get_gap_world_start_z() -> float:
	return position.z + gap_start_z


## 获取断口在世界坐标系中的结束Z位置
func get_gap_world_end_z() -> float:
	return position.z + gap_start_z - gap_length

## 初始化路段
## p_has_gap: 是否有断口
## p_gap_length: 断口长度（默认使用 BASE_GAP_LENGTH）
func setup(p_has_gap: bool, p_gap_length: float = BASE_GAP_LENGTH) -> void:
	has_gap = p_has_gap
	gap_length = clampf(p_gap_length, BASE_GAP_LENGTH, SEGMENT_LENGTH - 8.0)
	if has_gap:
		# 断口位置在路段中间区域随机（留出前后边距）
		var margin := 4.0
		gap_start_z = -randf_range(margin, SEGMENT_LENGTH - margin - gap_length)
	_build_road()


## 构建路面的网格和碰撞体
func _build_road() -> void:
	if not has_gap:
		# 整段路面
		_create_road_piece(Vector3(0, 0, 0), SEGMENT_LENGTH)
	else:
		# 断口前的部分
		var front_length := absf(gap_start_z)
		if front_length > 0.01:
			_create_road_piece(Vector3(0, 0, 0), front_length)

		# 断口后的部分
		var back_start_z := gap_start_z - gap_length
		var back_length := SEGMENT_LENGTH - front_length - gap_length
		if back_length > 0.01:
			_create_road_piece(Vector3(0, 0, back_start_z), back_length)

		# 在断口位置添加一个可视的警示标记（红色边缘）
		_create_gap_marker(Vector3(0, 0, gap_start_z))


## 创建一段路面（网格 + 碰撞体）
func _create_road_piece(p_position: Vector3, p_length: float) -> void:
	var static_body := StaticBody3D.new()
	add_child(static_body)

	# 网格
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(ROAD_WIDTH, ROAD_HEIGHT, p_length)
	mesh_instance.mesh = box_mesh
	# 路面中心偏移：X居中，Y向下半个厚度，Z居中于该段
	mesh_instance.position = p_position + Vector3(0, -ROAD_HEIGHT / 2.0, -p_length / 2.0)
	static_body.add_child(mesh_instance)

	# 材质 - 深灰色路面
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.25, 0.3)
	mesh_instance.material_override = material

	# 碰撞体
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(ROAD_WIDTH, ROAD_HEIGHT, p_length)
	collision.shape = box_shape
	collision.position = mesh_instance.position
	static_body.add_child(collision)


## 创建断口边缘的红色警示标记
func _create_gap_marker(p_position: Vector3) -> void:
	# 断口前沿的红色条
	var marker_front := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(ROAD_WIDTH, 0.05, 0.2)
	marker_front.mesh = marker_mesh
	marker_front.position = p_position + Vector3(0, 0.01, -0.1)
	add_child(marker_front)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.1, 0.1)
	mat.emission_energy_multiplier = 0.5
	marker_front.material_override = mat

	# 断口后沿的红色条
	var marker_back := MeshInstance3D.new()
	marker_back.mesh = marker_mesh
	marker_back.position = p_position + Vector3(0, 0.01, -gap_length + 0.1)
	add_child(marker_back)
	marker_back.material_override = mat
