extends Node

@onready var start_menu: Control = $UI/StartMenu
@onready var settings_menu: Control = $UI/SettingsMenu
@onready var credit_menu: Control = $UI/CreditMenu

func _show_only_menu(menu:Control) -> void:
	start_menu.hide()
	settings_menu.hide()
	credit_menu.hide()
	menu.show()


func _on_goto_settings() -> void:
	_show_only_menu(settings_menu)


func _on_goto_credits() -> void:
	_show_only_menu(credit_menu)


func _on_back_to_start() -> void:
	_show_only_menu(start_menu)
