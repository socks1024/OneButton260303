extends Node

const GAME_WORLD_SCENE_PATH := "res://Content/Scene/World3D/game_world.tscn"
const LOADING_SCENE_PATH := "res://Content/Scene/UI/Loading/loading_scene.tscn"

@onready var world: Node = $World
@onready var ui: CanvasLayer = $UI

@onready var start_menu: Control = $UI/StartMenu
@onready var settings_menu: Control = $UI/SettingsMenu
@onready var credit_menu: Control = $UI/CreditMenu
@onready var pause_menu: Control = $UI/PauseMenu

## 跑步脚步声音效
var _sfx_footstep: AudioEvent = preload("res://Content/Art/Audio/Events/SFX/sfx_footstep.tres")
## 跑步脚步声音乐轨道名称
const FOOTSTEP_TRACK: StringName = &"Footstep"

var _game_root: Node = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.hide()

	# 从主菜单开始就播放跑步脚步声（贯穿整个游戏生命周期）
	AudioManager.play_music(_sfx_footstep, FOOTSTEP_TRACK, 0.5)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _game_root != null:
		if get_tree().paused:
			_resume_game()
		else:
			_pause_game()
	elif event.is_action_pressed("ui_cancel") and _game_root == null:
		get_tree().quit()


func _show_only_menu(menu:Control) -> void:
	ui.show()
	
	start_menu.hide()
	settings_menu.hide()
	credit_menu.hide()
	pause_menu.hide()
	
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 暂停游戏并显示暂停菜单
func _pause_game() -> void:
	get_tree().paused = true
	ui.show()
	pause_menu.show()
	pause_menu._show_main_panel()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 恢复游戏并隐藏暂停菜单
func _resume_game() -> void:
	get_tree().paused = false
	pause_menu.hide()
	ui.hide()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _on_goto_settings() -> void:
	_show_only_menu(settings_menu)


func _on_goto_credits() -> void:
	_show_only_menu(credit_menu)


func _on_back_to_start() -> void:
	_show_only_menu(start_menu)


func _on_new_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	ui.hide()
	_game_root = await SceneUtils.instantiate_scene_by_load_control(world,GAME_WORLD_SCENE_PATH,LOADING_SCENE_PATH)


## 暂停菜单 - 继续游戏
func _on_pause_resume_game() -> void:
	_resume_game()


## 暂停菜单 - 返回主菜单
func _on_pause_back_to_start() -> void:
	get_tree().paused = false
	_game_root.queue_free()
	_game_root = null
	_show_only_menu(start_menu)
