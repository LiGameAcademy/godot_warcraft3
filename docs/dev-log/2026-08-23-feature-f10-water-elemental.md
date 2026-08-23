# 开发日志 · 2026-08-23

> **分支**：`feature/f10-water-elemental`（HEAD `92ad8ca`）  
> **对比**：`master`（`8ee571f`）→ 本分支，**40 commits**，约 **397 文件**，+33k / −3k 行  
> **远端**：`origin/feature/f10-water-elemental`

---

## TL;DR

一条从「能造兵、能训兵」走到「能打、能放英雄技」的竖切分支：建造/训练/HUD 先跑通，资产管线（蒙皮、挂点、PE2）补齐，C0 战斗 + 野怪 AI 落地，F10 大法师水元素及后续英雄/支援技能 Phase A–C 完成，HUD 接上 Buff 条与自动施法覆盖层。

---

## 1. 建造与经济（Build）

| 主题 | 要点 |
|------|------|
| 选址与预览 | `preventPlace`、放置预览地面采样修复、开工脚印清场 |
| Powerbuild | 连续扣费、接近面朝、可换工地 |
| 表现 | 农民负资源/施工动画、建造幽灵钉住；Director 接线清场与交互 |
| 地图 | 建筑脚印渲染层、UberSplat、动态 pathing 刷新 |
| 测试 | 建造系统与地形 selftest 同步 |

相关文档：[BUILD_SYSTEM.md](../design/game/BUILD_SYSTEM.md)

---

## 2. 训练、集结与科技

- **7 槽训练队列**：全额取消退款、signal 驱动 HUD  
- **集结**：智能右键集结、标旗表现、移动反馈与集结点分离  
- **出生**：挤位与训练扣费校验  
- **科技**：`Requires` 门控训兵与铁匠解锁；路线图插入战斗 C0–C3 依赖说明  

---

## 3. HUD 与选中

- 小地图迁入 `game/hud`，队伍色与方框尺寸校正  
- 中栏选中信息、建造二级菜单；伐木改砍完善  
- **肖像**：MDX 相机 bake、中立黑灰底、主城档位动画；点选不批量 attach，肖像池不抢主相机  
- **战斗属性芯片**；Buff 条、**自动施法覆盖层**、OverHead 挂点（最新 commit）  
- **选中环**：悬停半透明环、抬高避免贴花遮挡；共享组件迁至 `scenes/selection`  

相关文档：[HUD.md](../design/game/HUD.md)、[SELECTION_RINGS.md](../design/game/SELECTION_RINGS.md)

---

## 4. 资产转换与模型表现

| 主题 | 要点 |
|------|------|
| 动画 | 驼峰 Sequence 名、`animkeys` sidecar、Global Sequence 独立时钟（旗/钟） |
| 蒙皮/挂点 | Stand rest、IBM=I、Tip = pivot 厘米；大法师杖尖/粒子对齐 |
| PE2 | 打进 `.scn`（弃用独立 pe2.tscn）；`PE2_GODOT.md` 字段映射与未做项 |
| TeamGlow | 杖尖 shader 提亮；Weapon 挂点 **排名**（修圣骑士光晕挂右手）；主城 Portrait 背景 **不造** 常显 `*_GlowBillboard` |
| 烘焙 | `export_model_scenes` / `wc3_scn_pe2` / `wc3_scn_rebucket`；Footman 等模型接入 |
| 门面 | `Unit` 实体根、模型门面迁出 map；Stance×Activity 动画层 |

相关文档：[MDX_SKINNING_GODOT.md](../design/asset-convert/MDX_SKINNING_GODOT.md)、[PE2_GODOT.md](../design/asset-convert/PE2_GODOT.md)、[ATTACHMENTS_BAKE.md](../design/asset-convert/ATTACHMENTS_BAKE.md)

---

## 5. 战斗 C0 与单位 AI

- **C0 战斗框架**：伤害管线、攻击/弹道、Forward+ 与 Decal 脚印  
- **弹道与查询**强化；运行时日志安静化  
- **野怪 AI**：leash 超距停攻归巢；农民 **民兵变身**（无兵营验收）  
- **merge**：combat-projectile 分支并入 unit-ai  

相关文档：[COMBAT_SYSTEM.md](../design/game/COMBAT_SYSTEM.md)、[UNIT_AI.md](../design/game/UNIT_AI.md)

---

## 6. F10 技能系统（本分支命名由来）

Phase A–C 已落地（见 [ABILITY_SYSTEM.md](../design/game/ABILITY_SYSTEM.md)）：

| 能力 | 说明 |
|------|------|
| **AHwe 水元素** | SLK def + 点地召唤 + 寿命 → Death |
| **AHbz 暴风雪** | 引导施法 + 区域/受击表现 |
| **AHab 辉煌光环** | 被动回蓝 + 命令卡占位 |
| **AHmt 群体传送** | 寿命管线 |
| **山丘四技能** | AHtb / AHtc / AHbh / AHav + `target_kind` 路由 |
| **牧师/女巫 P0** | 治疗/减速等 + **自动施法切换** |
| **基础设施** | `AbilityBehaviorCatalog`、`AbilityFxCatalog`、`BuffHost`/`BuffCatalog`、各 `*Ability` 控制器 |

**未完成（Phase D–E）**：Effect 原子、`*Ability` 变薄、`AbilityTargetingService`、Director 瘦身。

---

## 7. 工具链

- `tools/asset-convert`：`convert-mdx.js` 大改（attachments / pe2 / geosetvis / bone_rest / collision）  
- `bake-model-scenes.mjs`；`export-godot-assets.mjs` 简化为 scn 主路径  
- 新增 **`tools/godot-mcp`**（Godot headless 自测 runner）  
- `anim_global_seq.test.mjs` 等单元测试  

---

## 8. 回归建议（打开 `tmp/` 下 .scn）

| 模型 | 路径 | 看什么 |
|------|------|--------|
| 大法师 | `tmp/Units/Human/HeroArchMage/` | 杖尖 TeamGlow + Attack 粒子 |
| 圣骑士 | `tmp/Units/Human/HeroPaladin/` | 光晕在 Weapon Ref，不在右手 |
| 步兵 | `tmp/Units/Human/Footman/` | Stand-1/2/**StandVictory**/Stand-4（无 Stand-3） |
| 主城 | `tmp/Buildings/Human/TownHall/` | Stand 无多余 GlowBillboard；Portrait-1 有背景板 |

---

## 9. 提交清单（`master..HEAD`，自旧到新）

<details>
<summary>40 commits（点击展开）</summary>

```
fdfc8db fix(build): 修复放置预览地面采样参数并同步建造文档
e8f21a1 建造系统开发
24346e9 feat(hud): 中栏选中信息与建造二级菜单，并完善伐木改砍
ec56ac5 refactor(selection): 抽出共享组件并将环/选择器迁至 scenes/selection
cbb51f3 fix(map): 建筑脚印渲染层、UberSplat 与动态 pathing 刷新
2e4cca0 fix(map): mesh 消毒、geoset 快照与选中环 scale
fe7537f fix(visual): 农民负资源/施工动画与建造幽灵钉住
c17beb2 feat(build): preventPlace 选址与开工脚印清场
76e34a6 feat(build): Powerbuild 连续扣费、接近面朝与可换工地
b3d6f74 feat(train): 集结点、出生挤位与训练扣费校验
8bf8905 feat(game): Director 接线建造清场、训练集结与交互装配
52e5615 test: 同步建造系统与地形自测
2c11d7d refactor(present): Stance×Activity 动画层、AppLog 与施工锤 bake 修复
2907197 feat(hud): 肖像 MDX 相机 bake、中立黑灰底与主城档位动画
af1ce8d feat(hud): 小地图独立场景迁入 game/hud，队伍色与方框尺寸校正
62e15bc fix(select/hud): 点选不批量 attach，肖像池不抢主相机
929f859 feat(rally): 智能右键集结、标旗表现与移动反馈分离
c88a40e feat(train/hud): 7槽训练队列、全额取消退款与 signal 驱动 HUD
bf178c5 feat(tech/build): Requires 门控训兵与铁匠解锁，路线图插入战斗 C0–C3
5d47089 docs(vertical): F8 依赖标明须先完成战斗 C0–C3
61a0cac chore: 提交集结旗场景，忽略 assets 根下误落的衍生资源
703edc1 feat(combat): 落地 C0 战斗框架，并切 Forward+/Decal 脚印
bc07ec3 feat(asset-convert+gameplay): 动画驼峰命名 / animkeys sidecar / Footman 模型接入 / 战斗 C0 落地
0185088 docs(pe2): 记下特效映射口径，并落地 ArchMage 杖尖粒子与 TeamGlow。
6ccb2f6 chore: 收尾工作区——PE2 并入 .scn、GlobalSeq 旗钟、肖像相机与血条挂点。
5a62677 挂点排名和主城 Billboard
c41e612 refactor(present): 模型门面迁出 map，抽出 Unit 实体根
00fa227 feat(unit-ai): 野怪单位 AI + 农民民兵变身，便于无兵营验收
010814a feat(combat): 强化弹道与查询，并安静化运行时日志
d7abc99 feat(hud+present): 战斗属性芯片，并消除悬空 PE2 动画轨警告
2896398 feat(unit-ai): 野怪超 leash 停攻归巢，避免追到天涯海角
8bf3f50 feat(selection): 悬停半透明环，并抬高选中环避免贴花遮挡
23ee683 merge: combat-projectile（leash/HUD/PE2）并入 unit-ai
0ff61e5 feat(ability): F10 水元素 AHwe 全链路（SLK def + 瞄准施法）
7bacb8f feat(ability): 暴风雪 AHbz 引导施法 + 区域/受击表现
23bd403 feat(ability): 辉煌光环 AHab 被动回蓝 + 命令卡占位
f75a13b feat(ability): 群体传送 AHmt + 寿命管线 + 技能系统文档
3ecc7a1 feat(ability): 山丘之王四技能 AHtb/AHtc/AHbh/AHav + target_kind 路由
e184434 feat(ability): 牧师/女巫 P0 技能 + 自动施法切换
f7b3cfb feat(ability): F10 英雄技能、水元素与技能系统 Phase A-C
92ad8ca feat(hud): Buff 条、自动施法覆盖层与 OverHead 挂点
```

</details>

---

## 10. 下一步

1. 技能 Phase D：Effect 原子，减少每技 4+ 处改动。  
2. PE2 真 Tail / 发射率动画（大法师 Spell 焰仍偏近似）。  
3. 合并前：跑 headless selftest + Echo Isles 对战竖切（造兵 → 集结 → 水元素/暴风雪）。  
