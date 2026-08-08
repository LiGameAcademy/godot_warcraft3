# 可交互树木（MultiMesh → Promote → 受伤统一入口）

> 海量树用 MultiMesh 摆件；**第一次需要「可交互呈现」时**提升为独立 Node。  
> 伐木、投石车、选中黄环、死亡动画都走同一套 Runtime。  
> 所属层：Data=`Wc3DoodadList` · Logic=`TreeRuntime` · Present=`MapDoodadLayer` promote。  
> 相关：[SELECTION_RINGS.md](SELECTION_RINGS.md) · [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) · [doodad/README.md](../doodad/README.md) · [PATHFINDING_CHOICE.md](PATHFINDING_CHOICE.md)  
> 最后更新：2026-08-08

---

## 1. 背景与约束

| 事实 | 含义 |
|------|------|
| Echo Isles 等地图树木极多 | 必须默认 MultiMesh，不能全图 Node |
| MultiMesh 无独立 Node | 不能播动画、不能挂选中环、不能挂脚本 |
| 权威摆件数据已在 `Wc3DoodadList` | `creationNumber` 是跨 Present 的稳定 ID |
| pathing 已从 doodad 条目 blit | 与 GPU MultiMesh **解耦** |
| WC3：多人可同时砍同一棵树 | **无** `max_inside`；限制主要是站位 |
| WC3：投石车等可砸树 | 与伐木共用「扣生命 → 可能死亡」 |

**用户共识（已采纳）**

1. 交互时 MultiMesh → 同 Transform 独立模型（promote）。  
2. **统一入口**：凡树木扣血（采集砍击、未来投石车伤害等）都走 `TreeRuntime.apply_damage`；**首次掉血即 promote**（选中也可提前 promote 以便挂黄环）。  
3. 需明确防闪烁预案（见 §6）。

---

## 2. 目标与非目标

**目标（F1 伐木 + 远期破坏）**

- 右键树 → `HarvestLumber`：每 `Ahar.Dur1` 一击（`DataA` 伤树+得木）→ 攒满 `DataB` 容量 → 交主城（F5 再优先 Mill）→ 回树/附近树。  
- 多农民可同时砍同一 `creationNumber`。  
- 树有生命；扣至 0 → Death → **留树桩 Present** + 清 pathing（可走）；建造占格时再 `remove_stump`。
- 树桩 geoset：转换旁路 `*.geosetvis.json` 注入 AnimationPlayer `:visible`（Stand 隐桩 / Death 显桩）；promote 须 `snap_stand_geoset_visibility`，禁止 reveal_all。  
  - 活树根下露出木桩 = Geoset_1 未藏：常见于「无 geosetvis」或「树 Stand 被当成非骨骼动画而未 snap」。`MapModelCache` 应对有 Stand 的模型一律按 `:visible` 定格；MultiMesh 只抽 `visible` 的 Geoset。  
  - `NorthrendTree` 等若缺 `*.geosetvis.json`，需 `asset-convert --models-only --force --include "Doodads/Terrain/NorthrendTree/**"`。  
- 投石车等未来伤害走同一 `apply_damage`，不必再开一套「砸树 promote」。

**非目标（P0）**

- 闲置 demote 回 MultiMesh（可后置；P0 promote 后直到死亡都留 Node）。  
- 暗夜小精灵「一树一灵」。  
- 树再生 / 缠绕之树特殊规则。  
- 编辑器笔刷内完整 TreeRuntime（编辑器仍可只动 Data）。

---

## 3. 分层与模块

```text
Data      Wc3DoodadList / doodads.json     摆件只读（id, variation, pos, creationNumber, …）
Catalog   DestructableDataDef             max life、模型、pathTex、是否可伐
Logic     TreeRuntime（按 creationNumber） life、promoted、dead；apply_damage / ensure
Present   MapDoodadLayer                  MM 索引、hide instance、spawn Node
Game      HarvestController               站桩伐木订单（扣血走 TreeRuntime）
          UnitSelector                    选中树 → promote + 黄环（见 SELECTION_RINGS）
```

建议新文件（落地时再命名）：

| 路径 | 层 | 角色 |
|------|----|------|
| `game/scripts/logic/economy/tree_runtime.gd` | Logic | 单树状态；`apply_damage` |
| `game/scripts/logic/economy/tree_registry.gd` | Logic | 地图级 `creationNumber → TreeRuntime`；空间近邻查询 |
| `MapDoodadLayer` 增补 | Present | `instance↔cn` 映射、`promote(cn)`、`hide_mm_instance` |

---

## 4. 统一入口：`apply_damage`（核心契约）

**所有**对树的「有效打击」只进这里：

```text
TreeRegistry.apply_damage(creation_number, amount, source) -> DamageResult
  1. 若 dead → 忽略
  2. ensure_runtime(cn)          ## 读 Catalog max HP
  3. Present.ensure_promoted(cn) ## ★ 首次需要可动画/可挂环的 Present 时提升
  4. life = max(0, life - amount)
  5. 通知 Present：受击反馈（可选 Stand Hit / 轻微抖动）
  6. if life <= 0 → _kill(cn)
       - 立刻清 pathing（地面可走）
       - 播 Death → 定格树桩（Present 保留；建造再 remove_stump）
       - 通知所有仍指向此树的 HarvestController：换附近树或停
```

调用方：

| 来源 | 何时 | 备注 |
|------|------|------|
| 伐木每击 | `HarvestController` | `DataA` 伤树兼得木；满 `DataB` 才交货；死树留桩 |
| 投石车 / 技能 AoE | 未来战斗 | 只调 `apply_damage`，不直接碰 MultiMesh |
| 作弊 / 调试秒杀 | 工具 | 同上 |
| **仅选中、尚未砍** | — | **不做**：原作树不可左键选中；promote 只在伐木/伤害时 |

约定：

- **Promote 触发条件（Present）** = 伐木走近 / `apply_damage` 首次调用（**不含**左键选中）。  
- **不要**让 Harvest / 投石车各自写一套「删 MM + new Node」。  
- 扣血与负木：Logic 权威；农民背包仍由 `HarvestController` 写。

---

## 5. Promote 流程（Present）

### 5.1 建 MultMesh 时必做

建桶 `typeId#variation` 时维护双向索引（现状缺口）：

```text
mm_bucket → PackedInt32Array instance_index_to_cn
cn → { bucket_key, instance_index }
```

无此映射则无法按 `creationNumber` hide，只能整层 rebuild（不可接受）。

### 5.2 `ensure_promoted(cn)` 步骤（同帧内顺序固定）

```text
1. 若已有 promoted Node 且 valid → return node
2. 查 cn → (bucket, i)，读 MultiMesh.get_instance_transform(i)  ## 权威 xf
3. 用 Catalog GLB 实例化 Node3D（与单实例 doodad 路径同材质/阴影设置）
4. node.transform = xf（世界/父空间与 MM 一致；父节点建议同 Doodads 层）
5. node.set_meta("doodad_data", entry)；标记 tree / creationNumber
6. ★ 先把 Node 加入场景树并 force 可见更新（见 §6）
7. ★ 再 hide MM[i]（scale=0 或移到远裁剪外；勿先删后建造成空窗）
8. 登记 TreeRuntime.promoted = true
```

死亡移除：

```text
播完 Death → 定格树桩（不清 Present）→ pathing 已在 _kill 时清除；建造时 remove_stump
```

### 5.3 为何「扣血才 promote」足够覆盖投石车？

投石车命中 → `apply_damage` → 内部 `ensure_promoted` → 再播受击/死亡。  
选中黄环单独走 `ensure_promoted`（无伤害）。  
**没有第三条 Present 入口。**

---

## 6. 防抖动 / 闪烁预案（必读）

担心合理：同位置「MM 还在 + Node 已出」会双影；「MM 已灭 + Node 未就绪」会空一帧。

### 6.1 硬规则（P0 必须遵守）

| # | 规则 | 用意 |
|---|------|------|
| A | **先挂 Node，再 hide MM**（同进程帧内连续执行，中间不 `await`） | 避免空窗闪烁 |
| B | Node 的 `global_transform` **逐位复制**自 `get_instance_transform`（含 scale） | 避免位置跳变 |
| C | 与 MM 使用**同一 GLB / 同一 mesh part 集合与材质**（走现有 `MapModelCache`） | 避免换肤闪一下 |
| D | promote 当帧 **禁止** `rebuild_doodads_from_list` | 全量重建必闪 |
| E | hide 用「该 instance scale=0」或「transform 移出视锥」，**不要**压缩 `visible_instance_count` 打乱下标 | 保索引稳定 |
| F | Y 以当前 heightfield 结果为准；若 MM 与 Node 父空间不同，统一转到同一父下再比 xf | 防脚底陷地/飘起 |

### 6.2 进阶（若仍可见双影 / 爆闪）

| 预案 | 做法 | 何时上 |
|------|------|--------|
| **双缓冲一帧** | Node 创建后 `visible=false`，hide MM 的**下一帧**再 `visible=true`（或反过来用 MM 多留 1 帧） | A 仍双影时 |
| **深度/排序** | 同坐标两套 mesh 时强制 Node `sorting_offset` 略前，或 MM hide 用自定义 alpha=0 | 半透叶子闪 |
| **预热缓存** | 首棵同 `typeId#variation` promote 时异步预载 GLB；真正交互用同步实例 | 首次砍树卡顿像「闪」 |
| **动画对齐** | promote 后若播 Stand，从第 0 帧或与「静态 geoset 姿态」一致的绑定姿势起；P0 可先静姿不播 | 姿态跳变 |
| **阴影** | Node 与 MM 的 `cast_shadow` 一致；切换帧避免两份阴影叠加深 | 脚下黑斑闪 |
| **禁止跨线程改 MM** | 只在主线程改 instance transform | 花屏 |

### 6.3 验收（闪烁专项）

- [ ] 摄像机贴脸盯一棵树，农民开始砍：无整棵消失一帧、无双树叠影超过 1 帧。  
- [ ] 连续砍倒多棵：无全图 doodad 闪白 / 整体重建。  
- [ ] 选中树（只 promote 不扣血）：黄环出现时树不抖。  
- [ ]（远期）投石车砸树：同样无空窗。

### 6.4 回退策略

若某 tileset 树 GLB 与 MM 分片不一致导致无法无缝 promote：该 `typeId` 可降级为「加载时对可伐树不用 MM、直接单实例」（用 Catalog 旗标）。作为逃逸通道，不作为默认。

---

## 7. 与伐木订单的衔接

```text
HarvestLumber
  → 空间查询最近可伐树 cn（TreeRegistry）
  → 走到树碰撞外缘（负金再点树：不先交货，直接去砍）
  → 站桩：每 Ahar.Dur1 一击 apply_damage(DataA) + CarrySlot.gather(lumber)
       · 负重为单一资源 id + amount；采到异类时整槽替换（丢弃旧负重）
  → 满 DataB → 交货（ReceiveResources，按当前资源 mask）
  → 自动返回：原 cn 若 dead → 找附近下一棵
```

多人同树：多个 Controller 持有同一 cn；`apply_damage` 串行扣同一 `life`。  
**不要** FIFO 进树槽。

负重：`CarrySlot`（Logic）— 勿再拆 `_carry_gold` / `_carry_lumber`。  
金矿差异备忘：见 [GAMEPLAY_VERTICAL.md](GAMEPLAY_VERTICAL.md) F1；进矿隐藏 / `max_inside` **不**套用到树。

---

## 8. 实现顺序（建议）

1. **Present**：MM `cn↔index` 映射 + `ensure_promoted` + hide（含 §6 规则 A–F）。  
2. **Logic**：`TreeRegistry` / `TreeRuntime` + `apply_damage` / `_kill` + pathing 移除。  
3. **选中**：树拾取 + `ensure_promoted` + 黄环（[SELECTION_RINGS.md](SELECTION_RINGS.md)）。  
4. **HarvestLumber**：站桩循环 + 交货 + 回树。  
5. **文档/验收**：闪烁专项 + 多人同砍 + 砍倒换树。  
6. **远期**：投石车伤害源接入 `apply_damage`（Present 零改动）。

---

## 9. 验收清单

- [ ] 未交互树保持 MultiMesh，场景实例数不爆炸。  
- [ ] 首次砍击或选中后：独立 Node，MM 槽位隐藏，无闪烁（§6.3）。  
- [ ] 两农民同砍一树：双方都能出木；树 life 共享递减。  
- [ ] 树死：Death → 可走 pathing 更新；农民改砍邻居。  
- [ ] 金矿逻辑未被误改（仍 `GoldMineRuntime`）。

---

## 10. 相关代码（现状锚点）

| 路径 | 现状 |
|------|------|
| `scripts/map/presentation/layers/map_doodad_layer.gd` | MM 分桶；缺 cn 映射 / promote |
| `scripts/map/presentation/map_loader.gd` | pathing doodad blit；MM 精确删改弱 |
| `scripts/map/data/wc3_doodad_list.gd` | 权威 SoA |
| `game/scripts/logic/economy/harvest_controller.gd` | 仅采金 |
| `game/scripts/logic/command/unit_order.gd` | 已有 `HARVEST_LUMBER` 枚举 |
| `docs/doodad/HIVEWE_ALIGN.md` | MM 组内精确删改缺口 |
