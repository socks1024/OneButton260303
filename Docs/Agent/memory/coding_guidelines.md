# AI 编码规范与常见错误避免

> 本文档用于指导 AI 在本项目中编写 GDScript / GDShader 代码时避免常见错误。
> 每当进行代码编写或修改时，请参考此文档中的规则。

---

## 一、总则

### 1. 注释语言

- 代码中的注释使用**中文**。

---

## 二、GDScript 规范

### 1. 禁止使用自动类型推断 `:=`，必须显式标注类型

- **禁止**使用 `:=` 进行自动类型推断，所有变量声明**必须显式标注类型**。
- ✅ 正确：`var key: String = "hello"`
- ✅ 正确：`var rect: ColorRect = child as ColorRect`
- ✅ 正确：`var count: int = 0`
- ✅ 正确：`var value: Variant = dict.get("key")`
- ✅ 正确：`var node: Node = some_func()`
- ❌ 错误：`var key := "hello"`（禁止使用 `:=`）
- ❌ 错误：`var count := 0`（禁止使用 `:=`）
- 函数返回值也必须显式标注类型：
  - ✅ 正确：`func get_name() -> String:`
  - ❌ 错误：`func get_name():`（缺少返回类型标注）

---

## 三、GDShader 规范

### 1. 入口函数不能使用 return 返回值

- gdshader 的 `fragment()`、`vertex()`、`light()` 等入口函数返回类型为 **void**，不能使用 `return <值>` 返回值。
- 正确做法是直接赋值给内置变量。
- ✅ 正确：
  ```glsl
  void fragment() {
      COLOR = texture(TEXTURE, UV);
  }
  ```
- ❌ 错误：
  ```glsl
  void fragment() {
      return texture(TEXTURE, UV); // 编译错误：void 函数不能返回值
  }
  ```
- 注意：`return;`（不带值的提前返回）在 gdshader 中也是**绝对不允许的**，应使用条件分支代替。

---

## 四、工具与插件偏好

### 1. 日志处理

- 处理 log 逻辑时，**优先使用 clog 库**，而非原生的 `print` / `push_warning` / `push_error` 等方法。

### 2. 相机处理

- 处理相机逻辑和相机相关节点时，**优先使用 Phantom Camera**（插件），而非原生的 `Camera2D` / `Camera3D`。

---

## 五、数据与配置规范

### 1. 不要修改 @export 变量的默认值

- 如果遇到 `@export` 变量的数值看起来有问题，**不要直接在代码中修改其默认值**，也不要在 `.tscn` 文件中修改对应的覆盖值。
- 这些数值由设计人员在编辑器中调整，AI **只需在聊天中告知数值可能存在的问题**即可。

### 2. 场景静态优先，避免脚本动态生成

- 能静态写入场景的内容，**不要写在脚本的 `@onready`、`_ready` 等处动态生成**，优先直接在 `.tscn` 场景中完成挂载与配置。
- 能导出给用户在编辑器中调节的变量，**优先使用 `@export` 导出**，不要在脚本里写成不可调常量。
