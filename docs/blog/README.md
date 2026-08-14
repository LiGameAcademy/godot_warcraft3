# blog/ — 技术博客

> **角色**：从 godot_warcraft3 项目抽出"相对独立 + 完整"的技术点，整理成
> 适合对外分享的博客文章。**与 `docs/` 模块文档区分**——docs 是工程规范，
> blog 是技术叙事（"为什么这样做 + 踩过的坑 + 怎么权衡"）。
> 最后更新：2026-08-14

---

## 1. 选题清单

按"独立 + 完整 + 技术深度"排。

### 第一梯队（推荐先写）

| # | 选题 | 状态 | 写作素材 |
|---|------|------|----------|
| **01** | [GDScript Shader 跨引擎对照：HiveWE GLSL → Godot gdshader](01-shader-porting-hivewe-to-godot.md) | ✅ draft | `docs/shader/README.md` 9.6KB + `WATER_DEEP_ANALYSIS.md` 27.8KB |
| **02** | [F-PATH 寻路模块：5 纯函数 + F3 队形 + F4 战斗起步](02-pathing-modules-hivewe-to-godot.md) | ✅ draft | `game/scripts/logic/pathing/{steering_behaviors,path_arc,slope_speed,formation_follow,combat_steering}.gd` + 8 selftest 40 项 |
| **03** | 斜坡逻辑 4-phase：从 HivEWE side-ramp gate 到 Phase A/B/C/D | 📋 待写 | `wc3_ramp_paint.gd` + `HIVEWE_ALIGN.md` §3.1 |
| **04** | [魔兽特效怎么转到 Godot：PE2 / 显隐 / 绑骨旁路](04-wc3-effects-conversion.md) | ✅ draft | `convert-mdx.js` pe2/geosetvis/attachments + `wc3_pe2_particles.gd` + [ATTACHMENTS_BAKE.md](../design/asset-convert/ATTACHMENTS_BAKE.md) |
| **13** | Pathing data 层：从 WPM 文件到 GPU 纹理 | 📋 待写 | `scripts/map/data/wc3_pathing_map.gd` + `wc3_pathing_textures.gd` + `wc3_tga.gd` + `map_pathing_layer.gd` |

### 第二梯队

| # | 选题 | 写作素材 |
|---|------|----------|
| 04 | PE2 粒子系统：HivEWE ParticleEmitter2 → Godot GPU 粒子 | → 已并入 [04-wc3-effects-conversion.md](04-wc3-effects-conversion.md) |
| 05 | Doodad 大量 mesh 渲染：MultiMesh 边界 + INSTANCE_CUSTOM 错相位 | `map_doodad_layer.gd:52-58` + 多实例决策 || 06 | Melee Bootstrap：4 玩家主城开局（Echo Isles 经典地图放位）| `melee_bootstrap.gd` 168 行 + `game_director.gd` |
| 07 | minimap Phase 3：HiveWE 着色 live terrain raster | `e40b2ba` commit |

### 第三梯队（工程化）

| # | 选题 |
|---|------|
| 08 | Unit Defs 自动生成（`gen-unit-defs.gd` 434 行）|
| 09 | MapBuildContext 体系（4 个 layer 的 build 契约）|
| 10 | W3E DOO 格式解析（`doodads.json` schema）|
| 11 | EditorInputRouter：WE 风格 input 路由 |
| 12 | "复刻 + 锦上添花"方法论（4 份 HIVEWE_ALIGN 路线图）|

---

## 2. 风格约定

每篇博客 **3000-5000 字**，结构：

```text
1. 标题 + 副标题
2. TL;DR（3-5 行结论）
3. 背景（300-500 字：原作 / 痛点 / 为什么重要）
4. 核心方案（1500-2500 字：关键决策 + 精简代码片段）
5. 踩过的坑（500-1000 字：真实 bug + 解决）
6. 结果（300-500 字：性能 / 兼容性 / 后续）
7. 引用：相关 commit / doc 链接
```

**代码片段规则**：
- 每段最多 10-20 行（**不**是全文件）
- 关键逻辑必须有注释解释"为什么"
- 真实可运行（**不**是伪代码）

**语气**：
- 中文为主，技术术语保留英文
- 适度吐槽（"踩坑 1 小时" 比"经过细致排查"更有共鸣）
- 节奏紧凑，**不**堆字数

---

## 3. 写作流程

每篇博客按 3 步落地：

```text
1. 选 1 个选题 → 写 1 篇 draft（这次只到 01）
2. 老李审阅 + 选风格（精简 vs 详细 / 中文占比 / 吐槽浓度）
3. 批量写剩余选题（按老李节奏）
```

`docs/blog/` 与 `docs/{ramp,water,doodad,unit,hivewe,game,...}` 平行 —— blog 是
"对外发布"角度，docs 是"工程内部"角度。

---

最后更新：2026-08-05
