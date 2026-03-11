## 通用3D后处理场景分析（2D控制脚本对齐版）

### 后处理效果（3D）

3D 后处理采用与 2D 后处理一致的“场景化 + 根控制器”组织方式：

- 使用一个独立的 3D 后处理场景（例如 `post_processing_3d.tscn`）
- 控制器脚本挂在场景根节点（建议命名 `PostProcess3DController`）
- 根节点下挂载多个后处理体积子节点（每个子节点绑定一个 shader）
- 业务脚本只与根控制器交互，不直接写子节点 shader 参数

该方案用于模板默认实现，优先保证简单、稳定、易扩展。

### 设计方式（对齐2D控制脚本）

3D 控制器按 2D `post_process_controller.gd` 的核心思路设计：

- **自动扫描子节点**：在 `_ready()`（或进入树后）自动收集后处理体积子节点
- **效果列表缓存**：维护 `_effects`（效果名、参数元信息、默认值）
- **运行时参数缓存**：维护 `_param_values`（`effect/param -> value`）
- **运行时开关缓存**：维护 `_enabled_states`（`effect -> bool`）
- **统一参数入口**：通过控制器 API 读写参数并同步到对应材质

### 场景结构

推荐结构如下：

```mermaid
flowchart LR
  A[PostProcess3DController Root] --> B1[Volume_Bloom]
  A --> B2[Volume_Vignette]
  A --> B3[Volume_ColorGrading]
  B1 --> C1[ShaderMaterial_Bloom]
  B2 --> C2[ShaderMaterial_Vignette]
  B3 --> C3[ShaderMaterial_ColorGrading]![1773230524867](image/PostProcessVolumeAnalysis/1773230524867.png)![1773230528602](image/PostProcessVolumeAnalysis/1773230528602.png)
```

- `PostProcess3DController`（根节点）
  - 自动扫描并注册子节点效果
  - 统一提供开关、参数、重置、查询接口
- `Volume_*`（子节点）
  - 每个节点只承载一个 shader 效果
  - 接收根控制器下发参数并应用到材质

### 运行时 API（根节点）

为与 2D 控制脚本保持一致，3D 推荐提供以下公共方法：

#### 开关控制

- `enable_all()` - 启用所有后处理效果
- `disable_all()` - 禁用所有后处理效果
- `enable_effect(effect_name: String)` - 启用指定效果（传入子节点名）
- `disable_effect(effect_name: String)` - 禁用指定效果

#### 参数控制

- `set_effect_param(effect_name: String, shader_param: String, value: Variant)` - 设置指定效果 shader 参数
- `get_effect_param(effect_name: String, shader_param: String) -> Variant` - 获取指定效果 shader 参数

#### 恢复默认值

- `reset_effect_param(effect_name: String, shader_param: String)` - 恢复指定效果的单个参数
- `reset_effect_params(effect_name: String)` - 恢复指定效果的全部参数
- `reset_all_params()` - 恢复全部效果参数

#### 查询

- `get_effect_material(effect_name: String) -> ShaderMaterial` - 获取指定效果材质
- `get_effect_names() -> Array` - 获取所有效果名列表

### 添加新效果

添加一个新的 3D 后处理效果只需两步：

**第 1 步：编写 Shader**

创建新的后处理 shader（保持统一 uniform 命名规范）。 

**第 2 步：在3D后处理场景中添加子节点**

在 `post_processing_3d.tscn` 根节点下新增一个 `Volume_*` 子节点并绑定 shader。

完成后由根控制器自动识别，无需修改控制器对外 API。

### 性能与稳定性建议

- **体积数量建议**：默认 1~3 个效果体积，按平台档位裁剪
- **参数安全**：Clamp、uniform 存在性检测、默认值回退
- **更新策略**：仅在参数变化时同步材质，避免每帧无效写入

### 结论

3D 后处理现已与 2D 控制脚本在“设计方式 + API 命名”上对齐：

- 场景化组织（根控制器 + 多 shader 子节点）
- 自动扫描注册 + 参数/开关缓存
- 同名运行时 API，便于跨 2D/3D 复用调用习惯