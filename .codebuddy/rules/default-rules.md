---
# 注意不要修改本文头文件，如修改，CodeBuddy（内网版）将按照默认逻辑设置
type: always
---

## 开发要求

增加新功能或新逻辑前，先看文档和项目中现有的内容，能用预先做好的东西，就不要重复造轮子。

每次完成修改之后，检查所有的修改是否都被保留了。

## 编码规范

### GDScript
- 注释使用**中文**
- 禁止 `:=` 自动推断，变量和函数返回值**必须显式标注类型**
  - ✅ `var count: int = 0` / `func get_name() -> String:`
  - ❌ `var count := 0` / `func get_name():`

### GDShader
- `fragment()` / `vertex()` / `light()` 返回类型为 void，**禁止 `return <值>`，也禁止 `return;`**，用条件分支代替提前返回

### 工具偏好
- 日志：优先用 **clog**，不用 `print` / `push_warning` / `push_error`
- 相机：优先用 **Phantom Camera** 插件，不用原生 `Camera2D` / `Camera3D`

### 数据与配置
- `@export` 变量数值有问题时，**只在聊天中告知，不要自行修改代码或 .tscn**
- 能在场景中静态配置的内容，**不要在脚本中动态生成**
- 可调节的变量**优先 `@export` 导出**，不要写成脚本内不可调常量
