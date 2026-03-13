extends Node

const GAME_WORLD_SCENE_PATH := "res://Content/Scene/World3D/game_world.tscn"

@onready var start_menu: Control = $UI/StartMenu
@onready var settings_menu: Control = $UI/SettingsMenu
@onready var credit_menu: Control = $UI/CreditMenu

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_only_menu(menu:Control) -> void:
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
	SceneUtils.switch_scene_by_path(self, GAME_WORLD_SCENE_PATH)
