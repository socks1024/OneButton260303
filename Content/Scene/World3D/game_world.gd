extends Node3D
## 游戏世界主场景脚本，管理游戏流程。

@onready var player: Player = $Player
@onready var road_manager: RoadManager = $RoadManager
@onready var distance_label: Label = $UI/DistanceLabel
@onready var speed_label: Label = $UI/SpeedLabel
@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/VBoxContainer/GameOverLabel
@onready var fear_bar: ProgressBar = $UI/StatsPanel/VBoxContainer/FearBar
@onready var lost_bar: ProgressBar = $UI/StatsPanel/VBoxContainer/LostBar
@onready var eyes_overlay: ColorRect = $UI/EyesOverlay

const SCENE_PATH := "res://Content/Scene/World3D/game_world.tscn"

## 鬼怪生成器
@onready var _ghost_spawner: GhostSpawner = $GhostSpawner

## Gameplay 输入上下文（包含 jump 动作）
var _gameplay_context: InputContext = preload("res://Content/Data/Input/Contexts/gameplay_context.tres")

var _game_over := false
## 闭眼渐变 Tween 引用（用于打断上一个渐变动画）
var _eyes_tween: Tween
## 闭眼渐变持续时间（秒）
const EYES_CLOSE_DURATION := 0.3
## 睁眼渐变持续时间（秒）
const EYES_OPEN_DURATION := 0.2
## 失败原因枚举
enum DeathCause { NONE, FELL, FEAR_MAXED, LOST_MAXED }
var _death_cause := DeathCause.NONE

## 失败原因对应的文案
var _death_messages := {
	DeathCause.FELL: "你在黑暗中坠入了深渊……",
	DeathCause.FEAR_MAXED: "你被恐惧吞噬了……",
	DeathCause.LOST_MAXED: "你永远迷失在了梦境之中……",
}


func _ready() -> void:
	game_over_panel.hide()

	# 初始化闭眼遮罩：默认完全透明（睁眼状态）
	eyes_overlay.modulate.a = 0.0

	# 初始化数值条（恐惧值和迷失值从0开始）
	fear_bar.max_value = 100.0
	fear_bar.value = 0.0
	lost_bar.max_value = 100.0
	lost_bar.value = 0.0

	# 连接玩家信号
	player.player_fell.connect(_on_player_fell)
	player.eyes_state_changed.connect(_on_eyes_state_changed)
	player.fear_maxed.connect(_on_fear_maxed)
	player.lost_maxed.connect(_on_lost_maxed)

	# 连接数值变化信号
	player.stats.fear_changed.connect(_on_fear_changed)
	player.stats.lost_changed.connect(_on_lost_changed)

	# 将 RoadManager 引用注入给 Player，用于查询断口信息
	player.road_manager = road_manager

	# 初始化鬼怪生成器引用
	_ghost_spawner.player = player
	_ghost_spawner.spawn_parent = self
	player.ghost_spawner = _ghost_spawner

	# 启用 Gameplay 输入上下文，让 jump 动作可以传递到玩家
	InputManager.add_context(_gameplay_context)
	CLog.o("游戏世界已加载，开始奔跑！")


func _physics_process(_delta: float) -> void:
	if _game_over:
		return

	# 让道路管理器根据玩家位置和速度更新路段
	road_manager.update_road(player.position.z, player.current_speed)

	# 更新 UI
	var distance := player.get_distance_traveled()
	distance_label.text = "距离: %.1f m" % distance
	speed_label.text = "速度: %.1f m/s" % player.current_speed


## 闭眼/睁眼状态变化 — 使用 EyesOverlay 遮罩渐变
func _on_eyes_state_changed(is_closed: bool) -> void:
	# 打断上一个渐变动画（如果有）
	if _eyes_tween and _eyes_tween.is_valid():
		_eyes_tween.kill()

	_eyes_tween = create_tween()
	if is_closed:
		# 闭眼：遮罩从当前透明度渐变到 1.0（全黑）
		_eyes_tween.tween_property(eyes_overlay, "modulate:a", 1.0, EYES_CLOSE_DURATION)
	else:
		# 睁眼：遮罩从当前透明度渐变回 0.0（完全透明）
		_eyes_tween.tween_property(eyes_overlay, "modulate:a", 0.0, EYES_OPEN_DURATION)


## 恐惧值变化回调
func _on_fear_changed(current: float, max_val: float) -> void:
	fear_bar.max_value = max_val
	fear_bar.value = current
	# 根据百分比改变颜色：绿 → 黄 → 红
	_update_bar_color(fear_bar, current / max_val)


## 迷失值变化回调
func _on_lost_changed(current: float, max_val: float) -> void:
	lost_bar.max_value = max_val
	lost_bar.value = current
	_update_bar_color(lost_bar, current / max_val)


## 根据比例更新进度条颜色（值越高越危险：绿 → 黄 → 红）
func _update_bar_color(bar: ProgressBar, ratio: float) -> void:
	var color: Color
	if ratio < 0.5:
		# 绿 → 黄（0.0 ~ 0.5）
		var t := ratio / 0.5
		color = Color(t, 0.8 + 0.2 * (1.0 - t), 0.2 * (1.0 - t))
	else:
		# 黄 → 红（0.5 ~ 1.0）
		var t := (ratio - 0.5) / 0.5
		color = Color(1.0, 0.8 * (1.0 - t), 0.0)

	# 使用 StyleBoxFlat 设置 fill 颜色
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", style)


## --- 失败处理 ---

func _on_player_fell() -> void:
	_trigger_game_over(DeathCause.FELL)


func _on_fear_maxed() -> void:
	_trigger_game_over(DeathCause.FEAR_MAXED)


func _on_lost_maxed() -> void:
	_trigger_game_over(DeathCause.LOST_MAXED)


func _trigger_game_over(cause: DeathCause) -> void:
	if _game_over:
		return
	_game_over = true
	_death_cause = cause
	player.is_running = false

	# 停止鬼怪生成
	if _ghost_spawner:
		_ghost_spawner.stop()

	# 游戏结束时移除 Gameplay 输入上下文
	InputManager.remove_context(_gameplay_context.context_name)

	# 失败时确保遮罩隐藏，能看到 Game Over 画面
	if _eyes_tween and _eyes_tween.is_valid():
		_eyes_tween.kill()
	eyes_overlay.modulate.a = 0.0

	game_over_label.text = _death_messages.get(cause, "游戏结束")
	game_over_panel.show()
	CLog.w("游戏结束 - %s" % _death_messages.get(cause, "未知原因"))


func _input(event: InputEvent) -> void:
	# 游戏结束后按空格重新开始
	if _game_over and event.is_action_pressed("jump"):
		SceneUtils.switch_scene_by_path(self, SCENE_PATH)
