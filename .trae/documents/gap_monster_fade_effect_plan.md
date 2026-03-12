# GapMonster 淡入淡出效果优化计划

## 任务概述
为 GapMonster（断口怪物）添加淡入淡出动画效果，并实现时间可配置功能。

## 代码分析结果

根据对代码的分析：

- **怪物生成时机**：在 `road_segment.gd` 的 `_place_gap_monster()` 中实例化，当路段有断口时立即创建
- **怪物销毁时机**：在 `road_manager.gd` 中，当路段远离玩家时被 `queue_free()` 回收
- **配置方式**：使用 Godot 编辑器导出变量（`@export`）

## 实施步骤

### Phase 1: 更新 GapMonster 脚本
- [ ] 在 `gap_monster.gd` 中添加导出变量：
  - `fade_in_duration: float = 0.5` - 淡入持续时间（秒）
  - `fade_out_duration: float = 0.5` - 淡出持续时间（秒）
  - `fade_ease: Tween.EaseType` - 缓动类型（可选）
- [ ] 在 `_ready()` 中调用 `fade_in()` 实现淡入效果
- [ ] 添加 `fade_in()` 方法，使用 Tween 实现透明度从 0 到 1
- [ ] 添加 `fade_out()` 方法，使用 Tween 实现透明度从 1 到 0
- [ ] 添加 `fade_out_and_free()` 方法，淡出后自动释放

### Phase 2: 修改 RoadSegment 脚本
- [ ] 在 `_place_gap_monster()` 中保持现有实例化逻辑（淡入自动在怪物 _ready 中触发）
- [ ] 在 RoadSegment 被移除前（或添加通知回调），调用怪物的 `fade_out_and_free()`

### Phase 3: 场景配置（如需要）
- [ ] 检查 `gap_monster.tscn` 是否需要调整

### Phase 4: 测试验证
- [ ] 验证淡入效果：怪物生成时从透明渐变到可见
- [ ] 验证淡出效果：怪物消失前从可见渐变到透明
- [ ] 验证时间配置：调整导出变量，观察淡入淡出时长变化

## 技术实现细节

### 核心代码结构

```gdscript
# gap_monster.gd
@export var fade_in_duration: float = 0.5
@export var fade_out_duration: float = 0.5

func _ready():
    play("default")
    fade_in()

func fade_in() -> void:
    modulate.a = 0.0
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)

func fade_out() -> void:
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)

func fade_out_and_free() -> void:
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
    tween.finished.connect(queue_free)
```

## 默认配置建议
- 淡入时间：0.5 秒
- 淡出时间：0.5 秒
- 缓动函数：Ease Out（淡入）、Ease In（淡出）

---

计划已根据代码分析结果更新，请确认是否开始实施。
