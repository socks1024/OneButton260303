extends Node

const GAME_WORLD_SCENE_PATH := "res://Content/Scene/World3D/game_world.tscn"
const LOADING_SCENE_PATH := "res://Content/Scene/UI/Loading/loading_scene.tscn"

@onready var world: Node3D = $World
@onready var ui: Control = $UI

@onready var start_menu: Control = $UI/StartMenu
@onready var settings_menu: Control = $UI/SettingsMenu
@onready var credit_menu: Control = $UI/CreditMenu

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_only_menu(menu:Control) -> void:
	ui.show()
	world.hide()
	
	start_menu.hide()
	settings_menu.hide()
	credit_menu.hide()
	
	menu.show()


func _on_goto_settings() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only_menu(settings_menu)


func _on_goto_credits() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only_menu(credit_menu)


func _on_back_to_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only_menu(start_menu)


func _on_new_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	SceneUtils.switch_scene_by_load_control(world,GAME_WORLD_SCENE_PATH,LOADING_SCENE_PATH)
	ui.hide()
