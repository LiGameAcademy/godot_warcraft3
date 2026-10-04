# 资源导入与玩家端运行时导入重构路线图

状态：阶段 1 契约与资产范围收口；阶段 2 已有可验证的部分编译后端，尚未替换旧管线
分支：`codex/asset-pipeline-rebuild`  
日期：2026-09-28

脚本与版本进展（2026-09-29）：扫描现已纳入指定运行时目录的完整资产路径字面量，保留文件、行号及代码哈希，收集 22 条候选。默认范围增为 281 模型／522 纹理，缺失为 0。扫描／补齐支持显式 RoC／TFT；12 组候选规则与 Godot 一致，真实牧师两版本路径选择已验证。静态扫描不替代动态执行追踪，分段拼接、随机生成、mod 和源目录／转换缓存的实际选用差异仍待验证。

2026-09-29 最新进展：共享 [定义覆盖规则](DEFINITION_LAYERS.md) 已接入扫描器及建造列表、科技需求、命令卡、物品、地图／编辑器五个目录；默认保留基础表配置。`Wc3IdCatalog` 已按数据加载、模型路径、面板筛选拆分，所有相关文件低于 500 行。JS／Godot 合并及五目录隔离集成验证通过，包含两个 profile 下各 25 项地图目录检查。当前默认范围为 275 模型／519 纹理，全候选审计为 276／527，两者缺失及未解析均为 0。运行时 mod、动态脚本引用及 SLK／模型版本对应关系仍待核对，覆盖范围未全部闭合。

## 当前实现与验证边界（2026-09-28）

已建立 IR、bake 任务协议和独立 worker。当前 IR 已内嵌部分骨骼、动画、材质载荷，但仍混合原始格式数据和旧 sidecar 引用；不是完整、独立的跨格式语义契约。下文保留各批次进展，初始测试数字不代表当前全部能力。

真实 Footman 已通过源 MDX 转换、worker 保存、同进程结构比较及全新 Godot 进程重载：10 个节点、5 个网格/表面、40 根骨骼、13 条动画。缺失 IR 的失败测试确认旧输出未被覆盖。此结果只证明几何保存重载链路；不证明材质、挂点、特效或动画画面保真。worker 返回 `scope=geometry_roundtrip`、`deliverable=false`。

复现：设置 `GODOT` 为引擎可执行文件，执行 `node tools/asset-convert/src/worker-integration.test.mjs`。默认源目录为 `assets/.staging/wc3-assets`，可用 `ASSET_SOURCE` 覆盖。测试在 `tools/asset-convert/tmp/worker-*` 创建独立无 Autoload 的 Godot 项目，保留产物与日志；缺少引擎或真实源文件会失败，不自动跳过。

已确认后续执行顺序：资产范围与诊断 → 真实特效样本 → 提前验证导出游戏中的资源创建／保存／重载 → 批量导入与缓存可靠性 → 玩家首次导入 → 整图双重验收与主干迁移。原生核心与玩家导入流程尚未实现；原生核心／GDExtension 的具体职责依据发布运行时实测收敛，不仅凭未安装编辑器便排除 `.scn` 缓存。

资产范围进展：新增 [开发地图引用清单](DEVELOPMENT_MANIFEST.md)，从地图放置对象、人族开局种子和基础定义表递归追踪候选模型及纹理。每项保留引用原因、输入与源文件哈希；可接收新 worker 成功证据，核对源和输出哈希后标为部分编译。静态清单明确保留覆盖缺口，尚未完成动态引用与运行时覆盖规则的闭包，不能据此进入全量替换。

源文件补齐进展：确认原先 41 项缺失均可从本机补丁包精确读取，问题是档案文件列表不完整。新增按缺失路径解包并递归重扫的开发工具，两轮恢复 59 个源文件；当前候选范围为 276 个模型、521 个纹理，源缺失和模型解析失败为 0。重复运行不写入。仍有 17 条 Buff／Effect 引用未解析，既有缓存版本一致性、运行时定义覆盖和动态范围尚未闭合。

定义追踪进展（2026-09-29）：补入 `AbilityBuffData` 读取及缺表自动提取，17 条引用已解析；Func 覆盖层按保守候选纳入，并报告双方来源和值。修正注释路径误入清单及旧图标 TGA／BLP 别名识别。本机当前为 347 个对象、276 个模型、527 个纹理，缺失及未解析为 0，记录 211 处定义差异；尚未统一运行时覆盖策略，`coverage.complete=false`。本轮手动验收步骤见 [开发地图引用清单](DEVELOPMENT_MANIFEST.md#本轮手动验收)。

后续进展：IR 已内嵌骨骼姿态与挂点载荷；独立 `import_skeleton_compiler.gd` 消费当前 MDX/MDL 的扁平骨架数据，写入 rest 并创建静态挂点。Footman 生成 9 个挂点，场景增至 26 个节点。新进程验证 40 根骨骼的 rest 变换、挂点骨骼绑定和局部位置与 IR 一致。错误骨名阻断编译并保留旧场景。当前范围为 `geometry_skeleton_sockets`，仍为不可交付：挂点显隐动画、材质与特效尚未编译，也未完成游戏参考画面验收。此编译器只支持旧转换器的扁平骨架与单位逆绑定矩阵约定，其他输入适配器必须另行定义坐标及蒙皮契约。

显隐与跟随进展：IR 已内嵌动画载荷，worker 支持非全局序列的离散挂点显隐，为每个片段写入初始状态，避免切换动作时残留隐藏状态。Footman 的 7 个动画挂点 × 13 个片段生成 91 条轨道，新进程执行 Stand-1 → DecayBone → Stand-1，确认显示、隐藏、重新显示；固定时钟下 Attack-1 的 0、0.3、0.7 秒挂点位置与当帧骨骼变换一致，且确实发生位移。测试等待骨骼延迟更新完成后取样。连续插值、全局序列及被拉长的片段仍保留未编译诊断；不将这一局部支持标记为整库动画或视觉验收通过。下一批处理完整材质层语义及其编译。

材质基座进展：IR 保留原始材质层、层动画参数、纹理引用和 Geoset→材质绑定；worker 消费静态单层不透明、遮罩及普通透明材质。已按职责拆分旧转换器及查看器入口，相关维护代码文件均小于等于 500 行；查看器入口与 `boot.tscn` 同名，坐标轴独立成子场景。

队色与透明度进展（2026-09-28）：支持“全不透明的队色底层＋普通透明混合的漫反射覆盖层”，分别保留两层的受光／不受光标记、共同的剔除设置及双轴重复／夹取采样设置。队色纹理从真实源纹理转换，IR 记录相对 URI 和依赖；纹理及着色器随 `.scn` 保存，不依赖查看器再次补材质。支持非全局序列的阶梯、线性 Alpha 轨道，为每个动作写入初值，避免动作切换残留透明度。最终合成仍走不透明管线，覆盖层 Alpha 表示露出队色底层，不表示整个网格透明。查看器支持对新材质切换玩家颜色，仅修改预览实例。

Footman 实测：5 个表面完成材质编译，其中 1 个队色表面，13 条材质 Alpha 轨道。独立进程检查纹理重载、DecayBone 中段 Alpha=0.875、切回 Stand 恢复 1、队色覆盖层线性动画、A/B 实例和模板材质隔离。worker 无窗口保存重载与实际渲染器验证均检查错误日志；重载清理时保留材质引用直到节点销毁，避免着色器资源先于渲染实例释放。查看器 Forward+ 实测通过加载、玩家颜色切换、重播、清空和截图。牧师补充样本编译 4 个表面、1 个队色表面、8 条 Alpha 轨道；大法师编译 2 个表面、1 个队色表面，其未支持特效材质仍记录 `material_feature_pending`。

Geoset 显隐进展：worker 从 IR 内嵌的原始 `geoset_anims` 载荷直接编译非全局序列的二值离散显隐，不对旧 33ms 采样结果二次量化。每个动作写入初始值；无该动作关键帧时恢复默认可见，有延迟首帧时按现有源采样规则继承前值。Footman 的 5 个网格 × 13 个动作生成 65 条轨道；新进程验证 Stand-1、Death、DecayFlesh 的 0.1／0.2 秒、DecayBone、Stand-4 和切回 Stand-1。查看器实际渲染确认普通站立不再混入其他动作的网格。连续插值、全局序列或非二值 Alpha 的负向测试确认保留 `geoset_alpha_pending`，不会静默按阈值切换显隐。

连续曲线进展：对已编译的普通单层 Blend 材质，支持非全局序列的静态、阶梯和线性 Geoset Alpha／RGB。编译器将材质层 Alpha、Geoset Alpha 和颜色分为独立着色器参数，最终透明度为纹理 Alpha × 层 Alpha × Geoset Alpha；原层动画轨道保留关键帧并迁移到独立参数。每个动作写入默认值，切回无曲线动作恢复 Alpha=1、RGB=白色。合成 Blend 场景验证了重载后中点层 Alpha=0.6、Geoset Alpha=0.5、RGB=(0.5,0.5,0)，实际渲染颜色、切换复位及 A/B 材质隔离。此测试已纳入 `worker-integration.test.mjs`，并不替代真实特效的原作视觉对照。

当前仍不支持任意多层组合、单轴重复采样、全局／Hermite／Bezier 材质动画、动画纹理切换及 UV 动画。遮罩、不透明及多层队色材质的连续 Geoset Alpha／颜色仍保留诊断，不将其直接改为普通 Blend。粒子、Ribbon 与游戏内原作对照验收也未完成。因此保持 `deliverable=false`，不宣称整模型保真通过。下一批扩展真实特效样本，核对不同混合模式的曲线规则，再进入特效消费者。

真实资源测试（需要本地解包资产及 `$env:GODOT`；集成隔离检查会启动最小化渲染窗口）：

```powershell
node tools/asset-convert/src/worker-integration.test.mjs
node tools/asset-convert/src/worker-material-samples.test.mjs
```

结果生成在忽略目录 `tools/asset-convert/tmp/worker-*` 和 `material-samples-*`，测试会打印具体路径，不提交衍生模型。

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

### 阶段 0：分支和基线（分支已建立，资产范围仍在收口）

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

2026-09-29：新 worker 已生成牧师投射物、火球和大法师（地面／杖尖光晕）三个技术验收样本，接入加法材质、粒子轨和内嵌相机朝向处理。第二批增加回春术、复活和碎片投射物共 8 条 Ribbon，端点参考对照、独立场景重载、移动路径和实例隔离通过。仍待视觉及游戏内验收；Ribbon 的循环／拖帧历史策略和朝向／粒子拖尾仍有近似，复活其他材质尚未完整支持。样本入口、限制与操作步骤见 [FX_SAMPLE_ACCEPTANCE.md](FX_SAMPLE_ACCEPTANCE.md)。

1. 扫描开发地图和相关表，生成资产引用清单。
2. 创建 `model.ir.schema.json` 的第一版和字段状态定义。
3. 为现有 `convert-mdx.js` 增加 IR 输出旁路，不改变旧产物。
4. 建立 `bake-task.json` 和 `worker-result.json` 契约。
5. 选取 Footman、Priest projectile、Archmage projectile、英雄地面光晕、武器挂点光晕和 Ribbon 特效做迁移样本。
6. 从新 worker 迁移第一个 `.scn`，并由资产查看器验证。
7. 在确认 IR 字段稳定后，再开始原生导入核心设计和 GDExtension 骨架。

第一批任务不修改主干运行时路径，不删除旧 `.scn`，不在查看器中增加编辑能力。旧流程只作为对照，直到新流程完成代表样本和开发地图资产的验收。


## 10. 主干同步与下一轮目标（2026-10-03）

实际仓库已迁移至 `projects/blizzard-warcraft3/godot_warcraft3`，原路径不再有效。本轮从 `master` 提交公共依赖修复 `4ea2023f`，然后将主干快进合并到 `codex/asset-pipeline-rebuild`；没有文本冲突。此前的资产管线提交已经包含在主干中，不应再次复制实现。

### 本轮修复与验证

- 修复插件仓库同步时重复嵌套 `addons/<plugin>` 的路径，补齐启动计时器及治疗结果接口依赖。
- 恢复加载屏的纯显示接口 `begin/set_progress/finish`。主干迁移中误恢复了旧绑定接口，导致普通启动失败；快速启动 smoke 会绕过加载屏，无法发现该问题。
- 加入普通启动集成测试；加载屏生命周期测试仅检查自身补间，避免控制台 Autoload 动画造成误报。查看器缺少 Footman 样本时明确退出失败，避免空节点访问和挂起。
- 普通启动及快速启动均成功进入可玩地图，注册 86 个单位；治疗、指令请求、启动编排和加载屏回归通过。
- 重新生成牧师投射物、火球、大法师及三组 Ribbon 样本；独立场景重载、动画控制、资源隔离等技术检查通过。查看器用三个新特效与已有 Footman 场景组合测试，交互回归及实际渲染通过。Footman 是查看器基线，不作为本轮新编译器覆盖证明。

普通启动检查（仓库根目录 PowerShell）：

```powershell
python tools/workspace/sync_packages.py --app game
python tools/workspace/test_apps.py --godot 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe' --app game --case integration/selftest_normal_startup.tscn
```

当前开发地图仍有 10 个单位及肖像缺少 SCN，运行时使用 glTF fallback；部分地图纹理有缺失日志，退出时仍有 ObjectDB/资源未释放提示。启动通过不等于依赖完整或所有资产保真通过。特效仍需原作对照及游戏内视觉验收，保持未交付状态。

本次未完成的控制组、选择分组及指令排队修改独立保存在 Git stash：`待完善：控制组与指令排队，合并资产管线前保留 2026-10-03`（对象 `1f611c9fba8e9e0dcc315ac8ef2ae1f757eadaa2`）。它们涉及超出 500 行的既有文件和未完成的队列推进，不并入本次资产管线修复；以后恢复前需独立拆分和测试。stash 仅在本机保存。

### 下一轮：导出游戏中的编译与缓存闭环

优先验证导出的 Windows 游戏能否消费已生成 IR，在 `user://wc3-cache` 编译、保存并重新加载场景，全程无需玩家安装 Godot 编辑器或 Node.js。先证明现有 Godot 编译层的运行边界，再决定原生源适配器的实施范围。

1. 审计编译入口及依赖，区分可随游戏导出的逻辑和仅编辑器可用的接口；所有不支持情况产生明确日志。
2. 使用真实静态/骨骼模型及牧师、Ribbon 样本建立最小导出实验。此阶段输入为预生成 IR，不宣称已经支持玩家直接读取 MPQ/MDX。
3. 在全新用户缓存目录完成首次生成、退出重启和重载；验证源内容、IR/schema、编译器版本及依赖变化能使缓存失效。
4. 覆盖缺失依赖、损坏 IR、失败重试及 A/B 实例隔离；产物和错误日志可定位，输入文件保持只读。
5. 用同一缓存在游戏和只读查看器检查结果。技术通过与视觉通过分别记录；证据通过后再推进原生源解析和首次启动引导。

其后按开发地图清单补齐缺失 SCN、收紧 fallback 门禁，继续修复 billboard 自转及粒子/Ribbon 历史近似。分支完结条件仍是导出端闭环、开发地图依赖覆盖和游戏内验收，不能仅以查看器能打开为准。


## 11. 导出端编译实验（2026-10-03）

已完成第 10 节的首个运行边界实验：独立 Windows **release** 应用能从外部预生成 IR + glTF/纹理编译真实 Footman、牧师投射物和回春术 Ribbon，将 SCN 保存到 `user://wc3-cache/<本轮唯一目录>`。移开全部输入文件后，用新的发布进程重载成功；牧师粒子 A/B 参数隔离通过。运行阶段清空 PATH、GODOT 和 ASSET_SOURCE，不调用 Node 或编辑器，但这不是干净机器上的完整游戏安装验收。

实现分工：

- `tools/godot/import_scene_compiler.gd`：可由导出应用调用的 RefCounted 同步核心，返回结果和退出码，不负责退出进程。
- `tools/godot/import_worker.gd`：保留现有开发 CLI 契约，调用同一核心。
- `prepare-worker-project.mjs`：打包时为两个内嵌特效脚本复制 `.gd.source`，以原始 `.gd` 为唯一维护来源。
- `import_embedded_script.gd`：开发环境使用 source_code；发布包源码被剥离时使用 `.source`。发布 preset 必须包含 `include_filter="*.source"`。此步骤目前接入独立编译实验，尚未接入正式游戏发布构建。

实验发现并修复了发布差异：压缩 GDScript 的 source_code 为空时，旧逻辑会生成错误基类的内嵌脚本，导致 SkeletonModifier3D 无法挂载，同时编译结果仍显示成功。现在校验源码，并将特效编译的 error 诊断传播为失败。

复现（仓库根目录 PowerShell，需要已安装对应版本的 Windows export templates）：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$env:ASSET_SOURCE = Join-Path $PWD 'assets/.staging/wc3-assets'
node tools/asset-convert/src/exported-runtime.test.mjs
```

准备与导出阶段仍使用 Node 和编辑器；玩家阶段仅启动生成的 EXE。输出在 `tools/asset-convert/tmp/exported-*/report.json`，其中记录 EXE、结果和用户缓存绝对路径，均为本机生成产物，不提交原版资产。测试还检查输入内容哈希不变、损坏 IR 返回 `ir_invalid`、失败不覆盖已有良好缓存，以及恢复有效任务后的重试成功。另行导出不含源码 payload 的发布包，确认返回失败和 `billboard_script_invalid`，不会被误记为成功。查看器载入发布端生成的 Footman、牧师缓存后交互与实际渲染回归通过；查看器截图不代表原作视觉验收。

当前未完成：源 MPQ/MDX 的玩家端解析、正式游戏首次启动引导、完整 IR 结构校验、异步进度/取消、缓存复用与版本失效，以及完整游戏发布验收。产物仍为 `deliverable=false`；该实验不证明特效视觉保真。

下一轮先做持久缓存契约：纳入源文件、IR/schema、编译器和依赖签名；实现缓存命中/失效、临时产物校验后原子替换、损坏缓存重建，并用本轮 release 实验验证。随后把编译核心及源码 payload 打包步骤接入正式游戏构建，再按证据推进原生适配器和首次启动引导。


## 12. 缓存可靠性完成（2026-10-03）

新增 `import_cached_compiler.gd` 作为同步缓存入口，复用已有场景编译核心。开发 CLI 保持直接编译和原有固定输出路径；发布实验调用缓存入口。正式游戏接入仍属于下一步。

缓存签名覆盖：源签名所在的 IR 内容、可选原始源文件 `source_path` 的实际内容、IR/schema、glTF、buffer/纹理、IR 与 task 声明依赖、profile、规则/预期签名、引擎版本、编译器版本及编译实现内容。`prepare-worker-project.mjs` 生成 `import_compiler.source`，发布 preset 的 `*.source` 过滤器同时包含它。缺失或不可读的依赖明确失败，不返回陈旧缓存。

[Godot Windows 的 rename 实现](https://github.com/godotengine/godot/blob/master/drivers/windows/dir_access_windows.cpp)在覆盖目标文件时会先删除目标，不能以此实现安全覆盖。因此采用独立版本：

```text
任务 output_scene = user://wc3-cache/.../PriestMissile.scn（逻辑槽）
PriestMissile.scn.cache/
  <版本>.scn                校验成功的完整场景
  <版本>.json               最后发布的提交记录
  <版本>.pending.*          尚未提交的暂存文件
```

消费者必须读取结果的 `output_scene` 实际路径，不能拼接逻辑槽路径。场景保存、磁盘重载和输入签名复查完成后，先发布唯一场景文件，再发布唯一 JSON 提交记录；两次 rename 的目标均不存在，禁止覆盖。没有记录的孤立场景不被消费，旧提交保持可用。无需另增玩家端外部工具或原生扩展。

命中时验证最新提交的格式/缓存版本、签名、SCN SHA-256 以及结果的资产身份、profile、编译器版本和必要字段。返回 `cache.status=hit`；重建返回 `rebuilt` 并记录原因，如 `signature_changed`、`scene_corrupt`、`record_invalid`。损坏文件先检测哈希，不把它交给 ResourceLoader 引发解析错误。损坏 JSON 使用可恢复解析，明确作为缓存失效处理。

发布端测试覆盖重复调用不重写场景、源/IR/几何/纹理/依赖/规则/profile 的失效、真实重导出后的编译器版本和构建签名失效、缺失依赖、SCN 缺失/损坏、记录损坏/版本/身份不匹配、暂存残留、系统时钟回退、场景及记录提交失败、编译期间输入变化和跨进程重载。失败注入仅位于测试应用中；失败不替换旧提交。最终发布端 35 项缓存检查通过，Footman 开发 CLI 回归及新缓存在查看器中的交互/实际渲染回归通过。复现仍使用第 11 节的 `exported-runtime.test.mjs`，结果附 `cache-checks.json`。

缓存入口当前消费预生成 IR + glTF；暂不支持此入口直接缓存 GLB。旧已提交版本及异常退出留下的孤立文件不自动删除，正式游戏接入时另行制定容量和清理策略。没有改变查看器的只读定位，也没有将技术通过标记为视觉保真或可交付。

下一步为正式游戏接入：打包缓存入口及源码/构建签名 payload，按缓存结果的实际路径加载资产，并在正式导出游戏内复现缓存命中、失效、故障恢复和重载。

## 13. 正式游戏缓存接入（2026-10-03）

缓存编译入口已接入 `apps/game` 正式启动与 Windows release 构建。新增 `app/game_asset_import.gd` 消费版本化任务清单，在地图启动前编译/复用缓存，并通过游戏原有 `RuntimeAssets.load_packed_scene` 重载。全部任务成功后一次提交逻辑路径表；`ContentPaths` 将旧的资产逻辑路径映射到结果返回的实际缓存版本路径。导入失败不启动地图，也不安装半份路径表；对局运行中拒绝导入。路径表提交后只读，复制调用方字典，不允许重复切换。

新增启动参数：

- `--asset-root`：现有外部资源目录；在路径解析阶段生效，覆盖开发配置，避免 Autoload 先于 boot 加载到错误目录。
- `--asset-import-manifest`：包含 `manifest_version=1` 和非空 `tasks` 路径数组的 JSON；相对任务路径以清单目录为基准。
- `--asset-import-result`：写出结构化结果，包含每项诊断及实际缓存场景路径。
- `--asset-import-only`：完成编译、重载与游戏路径注册后退出，方便验证导入。
- 不使用 `--asset-import-only` 时继续正常 Loading；开发验证可以追加已有 `--smoke-test`。

这些参数是本阶段开发验收入口，不是最终玩家交互。输入仍是预生成 IR/glTF/bake task；开发地图的基础数据、纹理和未替换模型仍来自外部开发资源目录。成功结果保持 `deliverable=false`。

发布构建补充：

- `sync_packages.py` 在正式游戏同步时生成内嵌脚本源码及编译器签名 payload，维护源仍是原有脚本。
- Windows preset 包含 `*.source`，排除开发 override、测试、工具 JS、插件示例及旧原作模型/特效资源目录；原作资产不作为本轮新增发布资源提交。
- 补充游戏 .NET solution，匹配 Godot 的 Debug/ExportDebug/ExportRelease 配置及 Kernel 引用。
- 正式导出揭示 locale 目录被 `.gdignore` 排除：同步工具从同一权威 CSV/JSON 生成目录外只读 `.source`，本地化加载在原路径不可用时读取它。不维护第二套文案。

复现（仓库根目录 PowerShell，开发机器需要 Python、Node、Godot .NET、.NET SDK 和对应 Windows export templates）：

```powershell
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$env:ASSET_SOURCE = Join-Path $PWD 'assets/.staging/wc3-assets'
Remove-Item Env:GAME_BINARY -ErrorAction SilentlyContinue
node tools/asset-convert/src/game-runtime-import.test.mjs
```

测试自行同步、导出正式游戏，再准备 Footman、牧师投射物和回春术 Ribbon。发布进程清空 PATH、GODOT、ASSET_SOURCE，只启动游戏 EXE，验证首次导入、跨进程缓存命中、输入签名失效、缓存场景损坏重建、错误 IR 不破坏良好缓存、修正后重试，以及游戏按实际缓存路径加载并启动开发地图。退出码与脚本/构建错误同时校验，不能只看导出命令返回 0。每轮目录 `tools/asset-convert/tmp/game-runtime-*/` 保存 EXE、清单、逐次日志及最终 `report.json`。

手动检查最新成功报告中的 `binary` 与 `manifestPath`，启动该 EXE，传入 `--asset-root`、`--asset-import-manifest` 和 `--asset-import-result` 的实际路径；省略 `--headless`、`--asset-import-only`、`--smoke-test` 即进入正常 Loading 和地图。报告 `result.paths` 中的缓存 SCN 可直接放入只读查看器检查。不得将自动启动通过记为游戏内特效视觉验收。

本轮自测：正式 Windows release 的 8 项集成检查、路径表隔离/提交和导入保护边界测试、正常 Loading → 可玩地图回归、查看器帧数/循环/节点树/动画元数据/六向视图及实际渲染均通过。地图启动生成 86 个单位。现有悬崖、UberSplat 纹理和部分旧 SCN 缺失/占位告警仍存在；编辑器导出与正常退出时的 ObjectDB/resources 清理告警也未在本轮消除。这些不等于资源完整或视觉验收通过。

手动打开最新成功的正式游戏构建：

```powershell
$reportFile = Get-ChildItem tools/asset-convert/tmp/game-runtime-*/report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$report = Get-Content $reportFile.FullName -Raw | ConvertFrom-Json
$assetRoot = Join-Path $PWD 'assets'
$resultFile = Join-Path $reportFile.DirectoryName 'manual-import.result.json'
& $report.binary -- --asset-root $assetRoot --asset-import-manifest $report.manifestPath --asset-import-result $resultFile
```

下一步：确定发布进程中的源资产适配入口，先从原版路径读取开发地图所需资产并产生 IR/依赖，明确归档读取、格式解析和 Node 开发工具的边界，再接入首次启动 UI、进度、取消和失败重试。之后才扩展开发地图全量资产和游戏内视觉验收。缓存容量/旧版本清理、无输入清单的持久索引挂载及干净机器安装验收仍未完成。

## 14. 原版路径到发布游戏的源解析入口（2026-10-03）

已经验证随 Windows 游戏打包 Node/JS/Koffi/StormLib 的路线，复用现有适配器。发布游戏直接读取经典 MPQ 的四个真实样本及其纹理，产生带来源/哈希的 IR 和编译任务，再调用既有缓存入口；不要求玩家安装 Node 或编辑器。精确名称查找绕过不完整 listfile，补丁覆盖顺序与开发工具保持一致。请求越界、重复身份、缺失依赖及运行时缺失明确失败，失败不安装半份游戏资产路径表。

构建、手动验收、运行边界及限制见 [PLAYER_SOURCE_IMPORT.md](PLAYER_SOURCE_IMPORT.md)。当前同步命令行入口不等于玩家首次启动引导完成；完整开发地图仍需要现有外部资源数据。下一轮为后台进度/取消与首次启动 UI，再扩大开发地图覆盖和游戏内验收。

## 15. 后台导入与首次启动引导（2026-10-03）

Windows 发布游戏已实现只读源目录选择、源解析和逐场景编译子进程、阶段进度、取消、失败重试及持久索引恢复。只在完整批次可加载时挂载路径表，取消保留既有索引；下次启动验证版本和 SCN 哈希，无需重新解析源或保留 IR/纹理输入。编辑器默认开发启动、同步命令行验收和只读查看器保持各自职责。具体手动验收见 [PLAYER_SOURCE_IMPORT.md](PLAYER_SOURCE_IMPORT.md#首次启动与后台导入2026-10-03)。

本阶段仍只覆盖四个验收样本。下一阶段：从开发地图真实引用生成资源请求，覆盖单位/建筑/投射物/光晕、数据表和地形纹理，将地图启动对外部开发 assets 的依赖逐项移除；失败缺项需保留具体日志。之后再完成游戏内视觉验收、缓存容量清理、多进程协调和干净机器首次安装测试。


## 16. 开发地图覆盖与独立内容挂载（2026-10-04）

默认玩家请求从四样本扩大到 Echo Isles 摆放、人族建造/训练与技能物品关联、头像、运行时常量、地形及 UI。地图、SLK/TXT 和模型/纹理都从玩家同一经典安装来源产生；精确 MPQ 读取补齐旧 listfile 遗漏。独立内容代保存哈希、覆盖报告和显式别名，与 SCN 路径表同时校验后挂载并发布索引，正式 release 排除开发数据，地图启动不再要求外部 `--asset-root`。

后台每批最多 16 个模型，继续沿用拥有子进程的取消及原子缓存发布。扩大范围发现并修复 Gnoll 式挂点层级、纯粒子模型的无缓冲/空动画输入，以及重复动画访问器引起的加载耗时；源动画样本不变。完整发布验收入口是 `game-development-import.test.mjs`；操作说明与覆盖边界见 [PLAYER_SOURCE_IMPORT.md](PLAYER_SOURCE_IMPORT.md#开发地图资源覆盖2026-10-04)。

本轮正式发布验收通过 449 个模型和 10,537 个内容文件；地图可直接由缓存启动。收尾次序：先做实际对局与原作视觉验收，同时测量启动哈希校验/场景预加载耗时，再补缓存容量/旧版本清理及并发导入保护，最后验证干净机器首次安装。其他地图/种族、地图内嵌资产覆盖及 CASC 作为另行扩展，不把当前开发地图覆盖标成全部资产保真完成。


## 17. 真实投射物壳分流与启动计时（2026-10-05）

统一 SCN 接入真实投射物壳，绕过旧粒子重挂、强制发射/循环及视觉替换，保留源控制；旧资产兼容几何计算按职责提取。移动、三轮循环、命中 Death 和英雄光晕截图技术验收通过，完整对局与原作视觉对照仍待验收。新增四段启动计时；已确认全量哈希、重复内容复核和场景加载为主要开销。下一轮先处理主线程复核耗时及重复工作，随后容量/并发保护与干净机器测试，不能将本轮计时视为优化完成。操作和限制见 PLAYER_SOURCE_IMPORT.md 最新章节。
