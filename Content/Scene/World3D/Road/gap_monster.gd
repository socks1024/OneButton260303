class_name GapMonster
extends AnimatedSprite3D
## 断口怪物装饰，放置在道路断口中央。
## 从场景中实例化，所有外观参数均可在编辑器中调整。

@export_group("淡入淡出效果")
@export var fade_in_duration: float = 0.5
@export var fade_out_duration: float = 0.5
@export var fade_in_ease: Tween.EaseType = Tween.EASE_OUT
@export var fade_out_ease: Tween.EaseType = Tween.EASE_IN
@export var fade_trans: Tween.TransitionType = Tween.TRANS_QUAD

var _current_fade_tween: Tween = null


func _ready():
	play("default")
	fade_in()


func fade_in() -> void:
	if _current_fade_tween != null and _current_fade_tween.is_valid():
		_current_fade_tween.kill()
	
	modulate.a = 0.0
	
	_current_fade_tween = create_tween()
	_current_fade_tween.set_ease(fade_in_ease)
	_current_fade_tween.set_trans(fade_trans)
	_current_fade_tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)


func fade_out() -> void:
	if _current_fade_tween != null and _current_fade_tween.is_valid():
		_current_fade_tween.kill()
	
	_current_fade_tween = create_tween()
	_current_fade_tween.set_ease(fade_out_ease)
	_current_fade_tween.set_trans(fade_trans)
	_current_fade_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)


func fade_out_and_free() -> void:
	if _current_fade_tween != null and _current_fade_tween.is_valid():
		_current_fade_tween.kill()
	
	if not is_inside_tree():
		push_error("GapMonster: fade_out_and_free() called but node is not in tree")
		queue_free()
		return
	
	_current_fade_tween = create_tween()
	if _current_fade_tween == null:
		push_error("GapMonster: Failed to create tween")
		queue_free()
		return
	
	_current_fade_tween.set_ease(fade_out_ease)
	_current_fade_tween.set_trans(fade_trans)
	_current_fade_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	_current_fade_tween.finished.connect(func(): queue_free())
