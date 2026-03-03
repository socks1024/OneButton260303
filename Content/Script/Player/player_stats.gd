class_name PlayerStats
extends RefCounted
## 玩家数值管理，负责恐惧值和迷失值的增减逻辑。
## 恐惧值：看到鬼时增长，闭眼时下降，满值=被吓死。
## 迷失值：闭眼时增长，睁眼时下降，满值=永远迷失。

## 恐惧值变化信号（当前值, 最大值）
signal fear_changed(current: float, max_val: float)
## 迷失值变化信号（当前值, 最大值）
signal lost_changed(current: float, max_val: float)
## 恐惧值满信号（被吓死）
signal fear_maxed
## 迷失值满信号（永远迷失）
signal lost_maxed

## --- 恐惧值 ---
var fear_max := 100.0
var fear_current := 0.0
## 恐惧值增长速率（点/秒，看到鬼时）
var fear_gain_rate := 10.0
## 恐惧值下降速率（点/秒，闭眼时下降）
var fear_decay_rate := 3.0

## --- 迷失值 ---
var lost_max := 100.0
var lost_current := 0.0
## 迷失值增长速率（点/秒，闭眼时）
var lost_gain_rate := 5.0
## 迷失值下降速率（点/秒，睁眼时下降）
var lost_decay_rate := 4.0

## 是否已触发过满值（防止重复触发信号）
var _fear_maxed := false
var _lost_maxed := false


## 初始化数值
func reset() -> void:
	fear_current = 0.0
	lost_current = 0.0
	_fear_maxed = false
	_lost_maxed = false
	fear_changed.emit(fear_current, fear_max)
	lost_changed.emit(lost_current, lost_max)


## 增加恐惧值（睁眼看到鬼时每帧调用）
## multiplier: 倍率，可用于多只鬼叠加
func gain_fear(delta: float, multiplier: float = 1.0) -> void:
	if _fear_maxed:
		return
	fear_current += fear_gain_rate * multiplier * delta
	fear_current = minf(fear_current, fear_max)
	fear_changed.emit(fear_current, fear_max)
	if fear_current >= fear_max:
		_fear_maxed = true
		fear_maxed.emit()


## 增加迷失值（闭眼时每帧调用）
func gain_lost(delta: float) -> void:
	if _lost_maxed:
		return
	lost_current += lost_gain_rate * delta
	lost_current = minf(lost_current, lost_max)
	lost_changed.emit(lost_current, lost_max)
	if lost_current >= lost_max:
		_lost_maxed = true
		lost_maxed.emit()


## 降低恐惧值（闭眼时每帧调用）
func decay_fear(delta: float) -> void:
	if _fear_maxed or fear_current <= 0.0:
		return
	fear_current -= fear_decay_rate * delta
	fear_current = maxf(fear_current, 0.0)
	fear_changed.emit(fear_current, fear_max)


## 降低迷失值（睁眼时每帧调用）
func decay_lost(delta: float) -> void:
	if _lost_maxed or lost_current <= 0.0:
		return
	lost_current -= lost_decay_rate * delta
	lost_current = maxf(lost_current, 0.0)
	lost_changed.emit(lost_current, lost_max)


## 获取恐惧值百分比（0~1）
func get_fear_ratio() -> float:
	return fear_current / fear_max if fear_max > 0.0 else 0.0


## 获取迷失值百分比（0~1）
func get_lost_ratio() -> float:
	return lost_current / lost_max if lost_max > 0.0 else 0.0
