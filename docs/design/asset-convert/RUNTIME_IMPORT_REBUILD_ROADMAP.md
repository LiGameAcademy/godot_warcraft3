# 资源导入与玩家端运行时导入重构路线图

状态：已确认目标，开始阶段 0/1 实施  
分支：`codex/asset-pipeline-rebuild`  
日期：2026-09-28

## 当前实现与验证边界（2026-09-28）

已建立 IR 摘要旁路、bake 任务协议和几何编译 worker。当前 IR 仍是统计与旧 sidecar 引用集合，不是完整、独立的语义中间格式；worker 读取其版本和资产身份，但尚未消费特效等载荷。

真实 Footman 已通过源 MDX 转换、worker 保存、同进程结构比较及全新 Godot 进程重载：10 个节点、5 个网格/表面、40 根骨骼、13 条动画。缺失 IR 的失败测试确认旧输出未被覆盖。此结果只证明几何保存重载链路；不证明材质、挂点、特效或动画画面保真。worker 返回 `scope=geometry_roundtrip`、`deliverable=false`。

复现：设置 `GODOT` 为引擎可执行文件，执行 `node tools/asset-convert/src/worker-integration.test.mjs`。默认源目录为 `assets/.staging/wc3-assets`，可用 `ASSET_SOURCE` 覆盖。测试在 `tools/asset-convert/tmp/worker-*` 创建独立无 Autoload 的 Godot 项目，保留产物与日志；缺少引擎或真实源文件会失败，不自动跳过。

下一步：将 IR 从摘要升级为保留源语义的载荷，迁移材质、骨骼姿态和挂点消费者，再处理粒子与 Ribbon。原生核心与玩家导入流程尚未实现。玩家端能否直接用导出运行时生成/保存 Godot 资源，应通过导出版本实测决定，不应仅因未安装编辑器便预先排除 `.scn` 缓存。

## 1. 目标

项目最终需要作为独立游戏发布。玩家启动游戏时可以选择本机的 Warcraft III 原版资产目录，游戏随后完成资源检查、导入和缓存；玩家不需要安装 Godot 编辑器、Godot 命令行或 Node.js。

开发阶段继续使用 JavaScript 编排批量导入，必要时调用 Godot headless 生成和验证 `.scn`。玩家端使用不依赖编辑器的原生导入核心，并通过 Godot GDExtension 接入游戏运行时。

最终目标不是让 JavaScript 在玩家机器上运行，而是让开发期和玩家端共享同一套资源语义、缓存签名和验证规则。

## 2. 已确认的产品决策

- 通过适配器模式支持多种输入格式，包括 Warcraft III 资产、GLB/glTF 和未来自有资产。
- Warcraft III 原始来源、MPQ 优先级、文件哈希等追溯信息只服务开发和审计，运行时不依赖原始工程文件。
- 接受建立版本化的统一 Model IR（中间描述）。
- GLB 只作为内部几何缓存，最终运行时交付以 `.scn` 或玩家端运行时缓存为主。
- 保留 `fidelity` 与 `enhanced` 两种 profile。前者保留原始资产语义，后者允许使用更适合 Godot 的实现并改善视觉表现。
- 运行时允许 fallback，但必须记录日志。fallback 不应悄悄改变资源验收结论。
- 资产查看器是只读的独立交付判定工具，负责技术和预览验收。
- 自有资产采用新的项目规范，不要求模拟 MDX 结构。
- 性能预算先通过实际测量建立，不预先承诺固定帧率。
- 接受完全重建旧 `.scn`；重构在独立 Git 分支完成，稳定后再合并主干。
- 第一批规范覆盖开发地图实际引用的单位、建筑、装饰物、投射物、技能、光晕和其他特效资产。

## 3. 当前流程的主要问题

现有链路“解包 → MDX/BLP 转换 → GLB → Godot bake → 运行时修补”可以工作，但职责分散在 `tools/asset-convert`、`tools/godot`、`MapModelCache`、各类 Presenter 和查看器中，导致错误发生阶段难以定位。

当前主要不足：

1. GLB 承担了超出交换格式能力的 Warcraft 语义，材质层、纹理动画、GeosetAnim、PE2、Ribbon、挂点和光晕用途无法完整从 GLB 反推。
2. bake、运行时材质修正、队伍颜色、光晕重构和 fallback 存在交叉，`.scn` 的结果可能依赖运行时状态。
3. `MapModelCache` 既负责加载又负责懒 bake，不适合作为新的正式导入器。
4. 保真和增强尚未形成独立产物和缓存身份。
5. 光晕和特效仍有基于法线、名称和几何的启发式规则，缺少可追溯的语义分类。
6. 缓存签名和依赖闭包需要覆盖源、schema、规则、profile、shader、转换器及 Godot 版本。
7. 现有测试更偏向“能加载”，需要升级为“源特征保留、生成物重载、fallback 透明、查看器可交付”。

## 4. 目标架构

```text
输入适配器
  ├─ Warcraft III MDX/BLP/MPQ
  ├─ GLB/glTF
  └─ Project Native Asset
          ↓
统一 Model IR
          ↓
能力审计与自动分类
          ↓
几何 / 材质 / 动画 / 特效 / 挂点编译
          ↓
fidelity 或 enhanced profile
          ↓
开发期：Godot headless → .scn
玩家端：原生 runtime cache → GDExtension 资源
          ↓
资产查看器与游戏验收
```

### 4.1 共享导入核心

新增一个不依赖 Godot 和 Node.js 的原生导入核心（初期可选择 C++ GDExtension 兼容实现，具体语言在阶段 1 评估）：

- MPQ 读取和覆盖优先级；
- BLP 解码；
- MDX/MDL 解析；
- 统一 Model IR 生成；
- 依赖发现与源哈希；
- 能力诊断和结构化错误；
- 运行时缓存读写。

开发 CLI 和玩家 GDExtension 都调用这一核心，避免开发导入结果与玩家首次导入结果出现语义分叉。

### 4.2 开发期导入器

JavaScript 是开发期流程控制器，负责：

- 扫描来源和开发地图引用；
- 调用输入适配器；
- 生成和校验 Model IR；
- 规划批量任务、断点恢复和并发；
- 调用 Godot headless worker；
- 收集日志、生成 `.scn` 和审计报告；
- 运行资产查看器和游戏验收门禁。

Godot worker 只负责调用 Godot API：读取 IR 和几何缓存，创建 Godot 节点与资源，保存 `.scn`，重新加载并返回结构验证结果。它不读取 MPQ，不做来源分类，不执行游戏 Presenter，也不做隐式懒 bake。

### 4.3 玩家端导入器

玩家端不启动 Godot 编辑器、Godot headless 或 Node.js。游戏内 GDExtension 负责：

1. 引导玩家选择 Warcraft III 原版资产路径；
2. 验证路径、必要 MPQ 和版本；
3. 建立来源清单和哈希；
4. 按开发地图引用导入资源；
5. 把 Model IR 转成运行时可用缓存；
6. 支持进度、取消、失败重试和断点恢复；
7. 把 fallback 和缺失资源写入玩家日志；
8. 完成后交给游戏加载。

玩家端优先生成 `user://wc3-cache/` 下的运行时缓存，而不是重新生成开发用 `.scn`。如果后续确认导出项目中的 `ResourceSaver` 足够稳定，再将部分缓存优化为可重载 `.scn`，但这不是玩家导入的前置条件。

## 5. Model IR 初始契约

第一版 schema 需要能表达以下内容，字段可分批实现但不能静默丢弃：

```text
identity
source
geometry
skeleton
animations
materials
textures
geoset_visibility
texture_animations
particles
ribbons
attachments
team_color
glow_categories
events
dependencies
diagnostics
schema_version
```

每个字段都要有独立状态：

```text
parsed
exported
consumed
approximated
fallback
validated
```

不支持的字段必须进入诊断，不得因为没有对应 Godot 节点而从 IR 中删除。

## 6. 产物与缓存

开发期模型产物：

```text
asset-id/
  source.manifest.json
  model.ir.json
  geometry.glb
  textures/
  effects/
  model.fidelity.scn
  model.enhanced.scn
  runtime-manifest.json
  audit.json
```

玩家端缓存：

```text
user://wc3-cache/
  manifest.json
  models/
  textures/
  effects/
  ir/
  diagnostics/
```

缓存签名至少覆盖：

- 原始文件哈希；
- MPQ 覆盖顺序；
- 输入适配器版本；
- Model IR schema；
- 编译规则版本；
- profile；
- shader 和效果规则版本；
- Godot 游戏版本；
- 依赖资源哈希。

## 7. 阶段计划

### 阶段 0：分支和基线（当前开始）

- 在 `codex/asset-pipeline-rebuild` 中工作；
- 保留现有主干和未提交开发改动，不把它们混入重构提交；
- 记录当前导入器、Godot、资产查看器和代表模型的基线；
- 生成开发地图资产清单；
- 固定重构前的代表样本截图和加载结果。

完成条件：重构分支可独立回退，开发地图资产范围可核对，旧流程仍可作为对照。

### 阶段 1：统一 IR 与导入任务契约

- 建立 `model.ir.schema.json`；
- 将现有 MDX 转换结果映射到 IR；
- 为未知字段保留诊断和源定位；
- 实现确定性的 `bake-task.json` 与 `worker-result.json`；
- 将 source/profile/rules/schema 纳入缓存签名。

完成条件：代表样本可生成 IR；每个关键源特征都有 parsed/exported/consumed 状态。

### 阶段 2：Godot headless 编译后端

- 新建独立 worker，逐步替代 `MapModelCache.bake_model_scene()` 的导入职责；
- 迁移动画、骨骼、材质、PE2、Ribbon、挂点和依赖写入；
- worker 不执行游戏 Presenter 和运行时 fallback；
- 生成 fidelity/enhanced 独立结果；
- 保存后重新加载并验证结构。

完成条件：Footman、Priest projectile、Archmage projectile、英雄光晕和一个 Ribbon 特效可由新 worker 完成 bake。

### 阶段 3：原生导入核心

- 把 MPQ、BLP、MDX 和 Model IR 生成能力抽成不依赖 Godot/Node.js 的库；
- 提供开发 CLI 调用接口；
- 定义玩家 GDExtension 调用接口；
- 增加版本、进度、取消、错误和缓存 API。

完成条件：原生核心能在没有 Godot 编辑器和 Node.js 的环境中读取代表资产并生成有效 IR/运行时缓存。

### 阶段 4：玩家端导入和缓存

- 实现路径选择和 MPQ 验证；
- 从开发地图依赖清单生成导入任务；
- 写入 `user://wc3-cache`；
- 支持断点恢复、失败重试和日志；
- 游戏只消费已验证缓存。

完成条件：干净机器只安装游戏和 Warcraft III 原版资产，即可完成导入并进入开发地图。

### 阶段 5：资产查看器质量门禁

- 查看 IR、profile、runtime-manifest 和 fallback；
- 显示运行时场景树和自动生成节点；
- 区分 fidelity/enhanced；
- 输出技术通过、fallback、未验证和不可交付状态；
- 使用同一份运行时缓存做预览。

完成条件：查看器可以独立判定资源是否具备进入游戏的条件。

### 阶段 6：迁移与合并

- 按开发地图资产清单全量重建；
- 对比旧流程和新流程；
- 清理旧 `.scn` 和运行时 bake fallback；
- 在独立分支完成双应用和性能回归；
- 形成合并报告后再合并主干。

## 8. 验收门禁

单个资产必须分别记录：

```text
源解析通过
IR 生成通过
依赖完整
fidelity 编译通过
enhanced 编译通过（如适用）
.scn/运行时缓存重载通过
资产查看器技术通过
资产查看器视觉通过
游戏场景通过
fallback 记录
```

“运行时允许 fallback”不等于“资源无条件通过”。查看器必须显示 fallback；如果 fallback 改变关键视觉职责，则资源标记为需要修复。

## 9. 当前第一批实施任务

1. 扫描开发地图和相关表，生成资产引用清单。
2. 创建 `model.ir.schema.json` 的第一版和字段状态定义。
3. 为现有 `convert-mdx.js` 增加 IR 输出旁路，不改变旧产物。
4. 建立 `bake-task.json` 和 `worker-result.json` 契约。
5. 选取 Footman、Priest projectile、Archmage projectile、英雄地面光晕、武器挂点光晕和 Ribbon 特效做迁移样本。
6. 从新 worker 迁移第一个 `.scn`，并由资产查看器验证。
7. 在确认 IR 字段稳定后，再开始原生导入核心设计和 GDExtension 骨架。

第一批任务不修改主干运行时路径，不删除旧 `.scn`，不在查看器中增加编辑能力。旧流程只作为对照，直到新流程完成代表样本和开发地图资产的验收。
