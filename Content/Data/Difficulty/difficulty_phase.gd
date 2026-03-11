class_name DifficultyPhase
extends Resource
## 单阶段难度配置，保存为独立的 .tres 文件。
## 包含该阶段持续距离、曲线参数和常量参数，采样时自动判断类型。

# ---- 阶段区间 ----

## 该阶段持续的距离（米）
@export var distance: float = 200.0

# ---- 曲线参数（随阶段进度变化） ----

## 玩家速度曲线（X: 阶段进度 0~1, Y: 速度 m/s）
@export var speed_curve: Curve
## 断口出现概率曲线（X: 阶段进度 0~1, Y: 概率 0~1）
@export var gap_chance_curve: Curve
## 安全期时长曲线（X: 阶段进度 0~1, Y: 秒）
@export var safe_duration_curve: Curve
## 活跃期时长曲线（X: 阶段进度 0~1, Y: 秒）
@export var active_duration_curve: Curve

# ---- 常量参数（本阶段内固定不变） ----

## 睁眼看鬼时恐惧增速
@export var fear_gain_rate: float = 10.0
## 闭眼时恐惧衰减速度
@export var fear_decay_rate: float = 3.0
## 闭眼时迷失增长速度
@export var lost_gain_rate: float = 5.0
## 睁眼时迷失衰减速度
@export var lost_decay_rate: float = 4.0

# ---- 内部映射表 ----

## 统一参数映射表：参数名 → Curve 或 float
var _param_map: Dictionary


## 构建内部参数映射表（首次采样前自动调用）
func _build_param_map() -> void:
	_param_map = {
		"speed": speed_curve,
		"gap_chance": gap_chance_curve,
		"safe_duration": safe_duration_curve,
		"active_duration": active_duration_curve,
		"fear_gain_rate": fear_gain_rate,
		"fear_decay_rate": fear_decay_rate,
		"lost_gain_rate": lost_gain_rate,
		"lost_decay_rate": lost_decay_rate,
	}


## 在指定进度下采样某个参数的值。
## [param param_name] 参数名（如 "speed"、"fear_gain_rate"）
## [param progress] 阶段内进度 0~1
## [param fallback] 参数不存在时的回退默认值
func sample(param_name: String, progress: float, fallback: float = 0.0) -> float:
	# 懒初始化映射表
	if _param_map.is_empty():
		_build_param_map()

	var val: Variant = _param_map.get(param_name)
	if val is Curve:
		return val.sample_baked(progress)
	elif val is float:
		return val
	return fallback
