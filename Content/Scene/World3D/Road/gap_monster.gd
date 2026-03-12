class_name GapMonster
extends AnimatedSprite3D
## 断口怪物装饰，放置在道路断口中央。
## 从场景中实例化，所有外观参数均可在编辑器中调整。

func _ready():
	play("default")
