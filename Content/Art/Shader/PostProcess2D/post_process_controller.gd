@tool
## 后处理控制器 - 自动扫描版
## 自动从子节点的 ShaderMaterial 中读取所有 shader 参数并生成检查器面板
## 添加新效果只需：在场景中添加 BackBufferCopy + ColorRect（挂载 ShaderMaterial）即可
extends CanvasLayer
class_name PostProcessController

# ============================================
# 内部数据
# ============================================

## 效果列表：[{ "name": 节点名, "params": [{ "shader_param": uniform名, "type": 类型, "hint": hint, "hint_string": hint_string, "default": 默认值 }] }]
var _effects: Array[Dictionary] = []

## 运行时参数值：{ "节点名/shader_param": 值 }
var _param_values: Dictionary = {}

## 运行时启用状态：{ "节点名": bool }
var _enabled_states: Dictionary = {}

## 是否已完成扫描
var _scanned: bool = false

# ============================================
# 扫描子节点
# ============================================

## 扫描所有 ColorRect 子节点，提取 ShaderMaterial 参数
func _scan_effects() -> void:
	_scanned = true
	_effects.clear()

	for child in get_children():
		if not child is ColorRect:
			continue
		var rect := child as ColorRect
		var mat := rect.material as ShaderMaterial
		if not mat or not mat.shader:
			continue

		var effect_name: String = rect.name
		var params: Array[Dictionary] = []

		# 从 ShaderMaterial 的 property_list 中提取 shader_parameter/ 开头的属性
		for prop in mat.get_property_list():
			var prop_name: String = prop["name"]
			if not prop_name.begins_with("shader_parameter/"):
				continue

			var shader_param: String = prop_name.trim_prefix("shader_parameter/")

			# 过滤掉 sampler2D 等不应暴露的参数
			if _should_ignore_param(shader_param, prop):
				continue

			var default_value: Variant = mat.get_shader_parameter(shader_param)

			params.append({
				"shader_param": shader_param,
				"type": prop.get("type", TYPE_FLOAT),
				"hint": prop.get("hint", PROPERTY_HINT_NONE),
				"hint_string": prop.get("hint_string", ""),
				"default": default_value,
			})

			# 初始化参数值（用 shader 上当前的值作为默认）
			var key := effect_name + "/" + shader_param
			if not _param_values.has(key):
				_param_values[key] = default_value

		# 初始化启用状态（默认关闭）
		if not _enabled_states.has(effect_name):
			_enabled_states[effect_name] = false

		_effects.append({
			"name": effect_name,
			"params": params,
		})

	# 同步所有子节点的可见性到当前启用状态（编辑器预览也生效）
	for effect in _effects:
		var effect_name: String = effect["name"]
		var node := get_node_or_null(NodePath(effect_name)) as ColorRect
		if node:
			node.visible = _enabled_states.get(effect_name, false)

## 判断是否应忽略此 shader 参数
func _should_ignore_param(shader_param: String, prop: Dictionary) -> bool:
	# 始终过滤内置屏幕纹理采样器（不应暴露给用户）
	if shader_param == "SCREEN_TEXTURE":
		return true
	# 保留用户自定义的 sampler2D（如 transition_texture 等），不再一刀切过滤
	return false

# ============================================
# 生命周期 - 使用 _notification 确保编辑器和运行时都能正确扫描
# ============================================

func _notification(what: int) -> void:
	# 当节点进入场景树时，执行首次扫描
	if what == NOTIFICATION_ENTER_TREE:
		_scan_effects()
		notify_property_list_changed()
	# 当子节点顺序/数量变化时（编辑器中添加/删除子节点），重新扫描
	elif what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_scan_effects()
		notify_property_list_changed()

func _ready() -> void:
	# 运行时（非编辑器）初始化所有效果的可见性和参数
	if Engine.is_editor_hint():
		return

	for effect in _effects:
		var effect_name: String = effect["name"]
		var node := get_node_or_null(NodePath(effect_name)) as ColorRect
		if not node:
			push_warning("PostProcessController: 找不到效果节点 '%s'" % effect_name)
			continue

		# 设置可见性
		node.visible = _enabled_states.get(effect_name, false)

		# 同步所有 shader 参数
		var mat := node.material as ShaderMaterial
		if mat:
			for param in effect["params"]:
				var key = effect_name + "/" + param["shader_param"]
				var value: Variant = _param_values.get(key, param["default"])
				mat.set_shader_parameter(param["shader_param"], value)

# ============================================
# 动态属性系统 - 自动生成检查器面板
# ============================================

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	for effect in _effects:
		var effect_name: String = effect["name"]

		# 分组标题 = 节点名
		properties.append({
			"name": effect_name,
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP,
		})

		# 启用开关
		properties.append({
			"name": effect_name + "_enabled",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT,
		})

		# shader 参数
		for param in effect["params"]:
			var prop_name = effect_name + "_" + param["shader_param"]
			var prop_dict := {
				"name": prop_name,
				"type": param["type"],
				"usage": PROPERTY_USAGE_DEFAULT,
			}
			# 对 sampler2D（TYPE_OBJECT）类型参数，补充 Texture2D 提示信息
			if param["type"] == TYPE_OBJECT:
				prop_dict["hint"] = PROPERTY_HINT_RESOURCE_TYPE
				prop_dict["hint_string"] = "Texture2D"
			else:
				if param["hint"] != PROPERTY_HINT_NONE:
					prop_dict["hint"] = param["hint"]
				if param["hint_string"] != "":
					prop_dict["hint_string"] = param["hint_string"]
			properties.append(prop_dict)

	return properties

func _set(property: StringName, value: Variant) -> bool:
	var prop_str := str(property)

	for effect in _effects:
		var effect_name: String = effect["name"]

		# 处理启用开关
		if prop_str == effect_name + "_enabled":
			_enabled_states[effect_name] = value
			# 同步到场景预览（编辑器和运行时都生效）
			var node := get_node_or_null(NodePath(effect_name)) as ColorRect
			if node:
				node.visible = value
			return true

		# 处理 shader 参数
		for param in effect["params"]:
			var expected_name = effect_name + "_" + param["shader_param"]
			if prop_str == expected_name:
				var key = effect_name + "/" + param["shader_param"]
				_param_values[key] = value
				# 实时同步到 shader
				var node := get_node_or_null(NodePath(effect_name)) as ColorRect
				if node:
					var mat := node.material as ShaderMaterial
					if mat:
						mat.set_shader_parameter(param["shader_param"], value)
				return true

	return false

func _get(property: StringName) -> Variant:
	var prop_str := str(property)

	for effect in _effects:
		var effect_name: String = effect["name"]

		# 处理启用开关
		if prop_str == effect_name + "_enabled":
			return _enabled_states.get(effect_name, false)

		# 处理 shader 参数
		for param in effect["params"]:
			var expected_name = effect_name + "_" + param["shader_param"]
			if prop_str == expected_name:
				var key = effect_name + "/" + param["shader_param"]
				return _param_values.get(key, param["default"])

	return null

# ============================================
# 恢复默认值支持 - 检查器面板显示圆圈箭头按钮
# ============================================

## 判断属性是否可以恢复默认值（当值与默认值不同时显示恢复按钮）
func _property_can_revert(property: StringName) -> bool:
	var prop_str := str(property)

	for effect in _effects:
		var effect_name: String = effect["name"]

		# 启用开关：默认值为 false
		if prop_str == effect_name + "_enabled":
			return _enabled_states.get(effect_name, false) != false

		# shader 参数
		for param in effect["params"]:
			var expected_name = effect_name + "_" + param["shader_param"]
			if prop_str == expected_name:
				var key = effect_name + "/" + param["shader_param"]
				var current_value: Variant = _param_values.get(key, param["default"])
				return current_value != param["default"]

	return false

## 返回属性的默认值（点击恢复按钮时使用此值）
func _property_get_revert(property: StringName) -> Variant:
	var prop_str := str(property)

	for effect in _effects:
		var effect_name: String = effect["name"]

		# 启用开关：默认值为 false
		if prop_str == effect_name + "_enabled":
			return false

		# shader 参数
		for param in effect["params"]:
			var expected_name = effect_name + "_" + param["shader_param"]
			if prop_str == expected_name:
				return param["default"]

	return null

# ============================================
# 公共方法
# ============================================

## 启用所有后处理效果
func enable_all() -> void:
	for effect in _effects:
		set(effect["name"] + "_enabled", true)

## 禁用所有后处理效果
func disable_all() -> void:
	for effect in _effects:
		set(effect["name"] + "_enabled", false)

## 启用指定效果（传入节点名）
func enable_effect(effect_name: String) -> void:
	set(effect_name + "_enabled", true)

## 禁用指定效果（传入节点名）
func disable_effect(effect_name: String) -> void:
	set(effect_name + "_enabled", false)

## 获取指定效果的 ShaderMaterial
func get_effect_material(effect_name: String) -> ShaderMaterial:
	var node := get_node_or_null(NodePath(effect_name)) as ColorRect
	if node:
		return node.material as ShaderMaterial
	push_warning("PostProcessController: 未知的效果名称 '%s'" % effect_name)
	return null

## 设置指定效果的某个 shader 参数
func set_effect_param(effect_name: String, shader_param: String, value: Variant) -> void:
	set(effect_name + "_" + shader_param, value)

## 获取指定效果的某个 shader 参数
func get_effect_param(effect_name: String, shader_param: String) -> Variant:
	return get(effect_name + "_" + shader_param)

## 获取所有效果名列表
func get_effect_names() -> Array:
	var names: Array = []
	for effect in _effects:
		names.append(effect["name"])
	return names

## 恢复指定效果的指定参数到默认值
func reset_effect_param(effect_name: String, shader_param: String) -> void:
	for effect in _effects:
		if effect["name"] == effect_name:
			for param in effect["params"]:
				if param["shader_param"] == shader_param:
					var key := effect_name + "/" + shader_param
					_param_values[key] = param["default"]
					
					# 同步到 shader
					var node := get_node_or_null(NodePath(effect_name)) as ColorRect
					if node:
						var mat := node.material as ShaderMaterial
						if mat:
							mat.set_shader_parameter(shader_param, param["default"])
					
					# 通知属性系统更新
					notify_property_list_changed()
					return
	
	push_warning("PostProcessController: 未找到效果 '%s' 或参数 '%s'" % [effect_name, shader_param])

## 恢复指定效果的所有参数到默认值
func reset_effect_params(effect_name: String) -> void:
	for effect in _effects:
		if effect["name"] == effect_name:
			for param in effect["params"]:
				var key = effect_name + "/" + param["shader_param"]
				_param_values[key] = param["default"]
				
				# 同步到 shader
				var node := get_node_or_null(NodePath(effect_name)) as ColorRect
				if node:
					var mat := node.material as ShaderMaterial
					if mat:
						mat.set_shader_parameter(param["shader_param"], param["default"])
			
			# 通知属性系统更新
			notify_property_list_changed()
			return
	
	push_warning("PostProcessController: 未找到效果 '%s'" % effect_name)

## 恢复所有效果的所有参数到默认值
func reset_all_params() -> void:
	for effect in _effects:
		var effect_name: String = effect["name"]
		for param in effect["params"]:
			var key = effect_name + "/" + param["shader_param"]
			_param_values[key] = param["default"]
			
			# 同步到 shader
			var node := get_node_or_null(NodePath(effect_name)) as ColorRect
			if node:
				var mat := node.material as ShaderMaterial
				if mat:
					mat.set_shader_parameter(param["shader_param"], param["default"])
	
	# 通知属性系统更新
	notify_property_list_changed()
