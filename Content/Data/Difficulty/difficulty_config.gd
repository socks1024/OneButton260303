class_name DifficultyConfig
extends Resource
## 难度配置顶层资源（纯数据），管理阶段序列并提供统一的参数采样接口。
## 挂在 GameWorld 上，各系统通过 sample_param() 一行调用获取当前参数值。
## 运行时状态（阶段追踪、信号）由外部脚本管理，Resource 本身保持静态不可变。

# ---- 阶段序列 ----

## 有序阶段列表，每项引用一个独立的 DifficultyPhase .tres 文件
@export var phases: Array[DifficultyPhase] = []

# ---- 全局常量 ----

## 开局保护段数：前 N 段路不出断口
@export var safe_segments: int = 3

## 是否为无尽模式（false = 关卡模式，所有阶段跑完触发胜利）
@export var endless: bool = false


# ---- 查询方法 ----

## 阶段总数
func get_phase_count() -> int:
	return phases.size()

## 所有阶段的总距离（米）
func get_total_distance() -> float:
	var total := 0.0
	for phase in phases:
		total += phase.distance
	return total

## 根据距离计算当前应处于的阶段索引
## 返回值范围 [0, phases.size()]，等于 size 表示全部完成
func calc_phase_index(dist: float) -> int:
	var accumulated := 0.0
	for i in range(phases.size()):
		accumulated += phases[i].distance
		if dist < accumulated:
			return i
	return phases.size()

## 根据当前距离采样指定参数的值。
## [param param_name] 参数名（如 "speed"、"fear_gain_rate"）
## [param dist] 当前已跑距离（米）
## [param fallback] 无阶段或参数不存在时的回退默认值
func sample_param(param_name: String, dist: float, fallback: float = 0.0) -> float:
	if phases.is_empty():
		return fallback

	# 查找当前距离所在的阶段
	var accumulated := 0.0
	for i in range(phases.size()):
		var phase := phases[i]
		var phase_end := accumulated + phase.distance
		if dist < phase_end:
			# 在当前阶段内
			var local_progress := clampf((dist - accumulated) / phase.distance, 0.0, 1.0)
			return phase.sample(param_name, local_progress, fallback)
		accumulated = phase_end

	# 超出所有阶段 → 使用最后一个阶段，进度 = 1.0（冻结在末尾值）
	return phases[-1].sample(param_name, 1.0, fallback)
