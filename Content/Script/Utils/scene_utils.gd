class_name SceneUtils

## 快速实例化 PackedScene，可以传入 Callable 对节点进行初始化
static func quick_instantiate(parent:Node, p_scene:PackedScene, init_callable = null) -> void:
	var n = p_scene.instantiate()
	if init_callable && init_callable is Callable:
		init_callable.call(n)
	parent.add_child(n)

## 将 from 替换为 to 指定的场景，新场景将被添加到 from 的父节点下
static func switch_scene_by_path(from_scene:Node, to_scene_path:String) -> void:
	from_scene.queue_free()
	
	var parent_node:Node = from_scene.get_parent()
	
	var packed_new_scene:PackedScene = ResourceLoader.load(to_scene_path)
	quick_instantiate(parent_node, packed_new_scene)

## 通过加载界面加载场景，将 from 替换为 to 指定的场景，在 to 加载时，会以 load_scene 作为过渡
static func switch_scene_by_load_control(from_scene:Node, to_scene_path:String, load_scene_path:String, min_load_time:float = -1, confirm_time = -1) -> void:
	from_scene.queue_free()
	
	var parent_node:Node = from_scene.get_parent()
	
	var p_load_scene:PackedScene = ResourceLoader.load(load_scene_path)
	var load_scene:LoadControl = p_load_scene.instantiate()
	load_scene.path = to_scene_path
	if min_load_time > 0: load_scene.min_load_time = min_load_time
	if confirm_time > 0: load_scene.confirm_time = confirm_time
	load_scene.load_finish.connect(func(res):quick_instantiate(parent_node,res))
	parent_node.add_child(load_scene)
