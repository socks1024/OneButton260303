extends Node3D
## 游戏世界主场景脚本，管理游戏流程。

@onready var player: Player = $Player
@onready var road_manager: RoadManager = $RoadManager
@onready var _directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var distance_label: Label = $UI/DistanceLabel
@onready var speed_label: Label = $UI/SpeedLabel
@onready var game_over_panel: PanelContainer = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/VBoxContainer/GameOverLabel
@onready var distance_result_label: Label = $UI/GameOverPanel/VBoxContainer/DistanceResultLabel
@onready var fear_bar: ProgressBar = $UI/StatsPanel/VBoxContainer/FearBar
@onready var lost_bar: ProgressBar = $UI/StatsPanel/VBoxContainer/LostBar
@onready var eyes_overlay: ColorRect = $UI/EyesOverlay

const SCENE_PATH := "res://Content/Scene/World3D/game_world.tscn"

## 鬼怪生成器
@onready var _ghost_spawner: GhostSpawner = $GhostSpawner
## 全局虚空黑雾平面（静态布设在场景中，跟随玩家Z轴移动）
@onready var _void_fog: MeshInstance3D = $VoidFog

## Gameplay 输入上下文（包含 jump 动作）
var _gameplay_context: InputContext = preload("res://Content/Data/Input/Contexts/gameplay_context.tres")
## 主 BGM 音频事件
var _main_bgm: AudioEvent = preload("res://Content/Art/Audio/Events/BGM/bgm_escape_ghost.tres")

var _game_over := false
## 难度配置资源（在编辑器中设置，或在 _ready 中加载）
@export var difficulty_config: DifficultyConfig
## 当前阶段索引（-1 = 尚未开始，等于 phase_count = 全部完成）
var _current_phase_index: int = -1

## 进度条填充样式（只创建一次，运行时只改颜色）
var _fear_bar_style: StyleBoxFlat
var _lost_bar_style: StyleBoxFlat

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

	# 初始化进度条样式（只创建一次，后续只改颜色）
	_fear_bar_style = StyleBoxFlat.new()
	_fear_bar_style.corner_radius_top_left = 2
	_fear_bar_style.corner_radius_top_right = 2
	_fear_bar_style.corner_radius_bottom_left = 2
	_fear_bar_style.corner_radius_bottom_right = 2
	fear_bar.add_theme_stylebox_override("fill", _fear_bar_style)

	_lost_bar_style = StyleBoxFlat.new()
	_lost_bar_style.corner_radius_top_left = 2
	_lost_bar_style.corner_radius_top_right = 2
	_lost_bar_style.corner_radius_bottom_left = 2
	_lost_bar_style.corner_radius_bottom_right = 2
	lost_bar.add_theme_stylebox_override("fill", _lost_bar_style)

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

	# 将难度配置注入到各子系统
	if difficulty_config:
		player.difficulty_config = difficulty_config
		road_manager.difficulty_config = difficulty_config
		road_manager.player = player
		_ghost_spawner.difficulty_config = difficulty_config

	# 注入完成后再初始化子系统（它们的初始化依赖 difficulty_config 和 player）
	road_manager.initialize()
	_ghost_spawner.initialize()

	# 启用 Gameplay 输入上下文，让 jump 动作可以传递到玩家
	InputManager.add_context(_gameplay_context)

	# 播放主 BGM
	AudioManager.play_music(_main_bgm, &"main", 1.0)

	CLog.o("游戏世界已加载，开始奔跑！")


func _physics_process(_delta: float) -> void:
	if _game_over:
		return

	# 让道路管理器根据玩家位置和速度更新路段
	road_manager.update_road(player.position.z)

	# 让方向光跟随玩家Z轴移动，使光源始终在奔跑方向的前方
	_directional_light.global_position.z = player.global_position.z

	# 让虚空黑雾跟随玩家Z轴移动
	if _void_fog:
		_void_fog.global_position.z = player.global_position.z

	# 更新 UI
	var distance := player.get_distance_traveled()
	distance_label.text = "距离: %.1f m" % distance
	speed_label.text = "速度: %.1f m/s" % player.current_speed

	# 阶段追踪与胜利检测
	_update_difficulty_phase(distance)


## 闭眼/睁眼状态变化




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
		var t: float = ratio / 0.5
		color = Color(t, 0.8 + 0.2 * (1.0 - t), 0.2 * (1.0 - t))
	else:
		# 黄 → 红（0.5 ~ 1.0）
		var t: float = (ratio - 0.5) / 0.5
		color = Color(1.0, 0.8 * (1.0 - t), 0.0)

	# 直接修改已有样式的颜色，不重复创建对象
	if bar == fear_bar:
		_fear_bar_style.bg_color = color
	elif bar == lost_bar:
		_lost_bar_style.bg_color = color


## --- 难度阶段追踪 ---

## 根据当前距离更新阶段索引，检测阶段切换并判断胜利
func _update_difficulty_phase(dist: float) -> void:
	if difficulty_config == null:
		return
	var new_index := difficulty_config.calc_phase_index(dist)
	if new_index != _current_phase_index:
		var old_index := _current_phase_index
		_current_phase_index = new_index
		_on_phase_changed(old_index, new_index)

## 阶段切换回调 — 可在此添加演出、一次性效果等
func _on_phase_changed(old_index: int, new_index: int) -> void:
	var total := difficulty_config.get_phase_count()
	CLog.o("阶段切换: %d → %d (共 %d 阶段)" % [old_index, new_index, total])

	# 所有阶段跑完 & 非无尽模式 → 胜利
	if new_index >= total and not difficulty_config.endless:
		_trigger_victory()
		return

	# TODO: 在这里可以根据 new_index 添加阶段切换演出
	# 例如：
	# if new_index == 1:
	#     play_cutscene("chapter_2_intro")


## --- 胜利处理 ---

func _trigger_victory() -> void:
	if _game_over:
		return
	_game_over = true
	player.is_running = false

	# 停止鬼怪生成
	if _ghost_spawner:
		_ghost_spawner.stop()

	# 移除 Gameplay 输入上下文
	InputManager.remove_context(_gameplay_context.context_name)

	# 停止主 BGM
	AudioManager.play_music(null, &"main", 1.0)

	# 确保遮罩隐藏
	if _eyes_tween and _eyes_tween.is_valid():
		_eyes_tween.kill()
	eyes_overlay.modulate.a = 0.0

	var distance := player.get_distance_traveled()
	game_over_label.text = "你成功逃出了噩梦！"
	distance_result_label.text = "跑了 %.1f 米" % distance
	game_over_panel.show()
	CLog.w("游戏胜利！跑了 %.1f 米" % distance)


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

	# 停止主 BGM
	AudioManager.play_music(null, &"main", 1.0)

	# 失败时确保遮罩隐藏，能看到 Game Over 画面
	if _eyes_tween and _eyes_tween.is_valid():
		_eyes_tween.kill()
	eyes_overlay.modulate.a = 0.0

	var distance := player.get_distance_traveled()
	game_over_label.text = _death_messages.get(cause, "游戏结束")
	distance_result_label.text = "跑了 %.1f 米" % distance
	game_over_panel.show()
	CLog.w("游戏结束 - %s（跑了 %.1f 米）" % [_death_messages.get(cause, "未知原因"), distance])


func _input(event: InputEvent) -> void:
	# 游戏结束后按空格重新开始
	if _game_over and event.is_action_pressed("jump"):
		SceneUtils.switch_scene_by_path(self, SCENE_PATH)
