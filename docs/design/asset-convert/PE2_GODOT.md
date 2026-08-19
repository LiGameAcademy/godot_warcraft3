# MDX 特效 → Godot（PE2 / TeamGlow / 光）

> **层**：资源映射（`tools/asset-convert` sidecar）+ 表现烘焙（`export_model_scenes` / `MapModelCache`）。  
> **对照模型**：`Units/Human/HeroArchMage`（杖尖火花、施法焰、马蹄尘、脚底/杖尖 TeamGlow）。  
> **最后更新**：2026-08-19  
> **不是最终还原**：GPUParticles3D 只能近似 ParticleEmitter2；下文「未做」是下一轮优先项。

蒙皮与挂点插座见 [MDX_SKINNING_GODOT.md](MDX_SKINNING_GODOT.md)。小件 geoset / BoneAttachment 清单见 [ATTACHMENTS_BAKE.md](ATTACHMENTS_BAKE.md)（那份偏旗子/时钟，粒子细节以本文为准）。

---

## 1. 特效分三类，不要混进一个 JSON

| 原作 | Sidecar / 来源 | Godot | 映射脚本 |
|------|----------------|-------|----------|
| **ParticleEmitter2** | `*.pe2.json` | `GPUParticles3D` | **`Wc3Pe2Particles._make_emitter`**（唯一实现） |
| **TeamGlow**（ReplaceableId=2 geoset） | 材质名 `_rep2` / TeamGlow PNG，**不在 pe2.json** | 脚底 `ShaderMaterial` + 杖尖 `TeamGlowBillboard` | `MapModelCache._present_team_glow_mesh` |
| **Light** | `attachments.json` / glTF 灯 | `OmniLight3D` 等 | bake 时 `_reparent_lights_into_pe2` |
| **RibbonEmitter** | 基本未做 | — | 见 §5 |

`export_pe2_scenes.gd` 已弃用（单独 `pe2.tscn`）。粒子贴图 bake 进 `.scn`，不入库 tscn。

---

## 2. 管线

```text
MDX ParticleEmitters2
    → convert-mdx.js  writePe2Sidecar
    → assets/asset-converted/.../*.pe2.json   （不入库 git）
    → Wc3Pe2Particles.build_root_from_payload / _make_emitter
    → GPUParticles3D（先挂 Pe2Root）
    → bind_emitters_to_bones：有 bone 则挂到同骨 Attach_*/Tip（局部 I）
    → wc3_scn_pe2.gd：各 Sequence 写 :emitting（Visibility×Rate 采样成开关）
    → 打进 *.scn
```

运行时切动画：`AnimPlayback` → `Wc3Pe2Particles.apply_sequence`（无脉冲的全程发射器；有 vis/rate 脉冲的交给 Animation 轨）。

重烤单模型：

```text
cd tools/asset-convert
node src/cli.js --models-only --force --include "Units/Human/HeroArchMage/**"
```

编辑器看 `tmp/Units/Human/HeroArchMage/HeroArchMage.scn`（关掉再开）。不要打开平铺的 `tmp/Units/Human/HeroArchMage.scn`。

**层归属**：JSON 是 Catalog/资源映射产物；`GPUParticles3D` 与 glow mesh 是 Presentation；bake 脚本在 `scripts/tool/`。

---

## 3. `pe2.json` 字段 → Godot（已接）

顶层：`version`（当前 2）、`source`、`sequences[]`（name + interval 毫秒）。

每个 `emitters[]`：

| JSON | Godot | 备注 |
|------|--------|------|
| `name` | 节点名 | |
| `bone` | `pe2_bone` meta → BoneAttachment / Tip | 非空则跟骨，丢掉世界 `pivot_by_sequence` |
| `pivot` / `local_pivot` | 未绑骨时 `position` | **绑到 Tip 后局部为单位阵**（跟网格杖尖；与 MDX 发射器 Pivot 可能差一截） |
| `life_span` | `lifetime` | |
| `emission_rate` | `amount ≈ rate × life`（clamp 1–256） | 动画轨的 rate **不改 amount** |
| `speed` / `variation` | `initial_velocity` | 负 speed → 方向 −Y |
| `latitude` | `spread` 0–180 | WC3 锥角近似 |
| `gravity` | `gravity.y = -grav` | WC3 −Z → glTF −Y |
| `width` / `length` | 点发射或 BOX | **0,0 → POINT**（勿再强制 0.5 盒） |
| `filter_mode` 0/1 | Mix / Additive+Alpha | 其它 FilterMode 未分 |
| `rows` / `columns` | 粒子序列帧 | |
| `life_span_uv` | `anim_speed` / offset | 估整表比例，很粗 |
| `segment_color` + `alpha` + `time_middle` | `color_ramp` | Additive 另有 RGB×1.45 抬亮 |
| `particle_scaling` + `time_middle` | `scale_min` + `scale_curve` | Additive 且寿命短于 0.6s 再 ×1.35 |
| `texture` | albedo | `RuntimeAssets.load_converted_texture` |
| `visibility_keys` | Animation `:emitting` | 与 rate 合成开关 |
| `emission_rate_keys` | 只参与 **开/关** | 50→250 峰值喷量丢失 |
| `active_sequences` | meta；null=全程 | |
| `frame_flags` 2/3 或 bit1 | Tail：`align_y` + 拉长 Quad | `1` 当 Head，避免普攻火花被拧成拖尾 |
| `tail_length` | 拉长 aspect（×中段缩放） | 不是 WC3 真实 Tail mesh |
| `squirt` | `explosiveness=1` | |
| `flags` LineEmitter `0x20000` | 细 BOX | width/length=0 时仍走 POINT |
| `flags` XY Quad `0x100000` | 关粒子 Billboard | |

`flags` 里 Unshaded / SortFarZ / ModelSpace、`priority_plane`、`decay_uv`：**写入 JSON，代码基本不吃**。

HeroArchMage 三个发射器（对照用）：

| 节点 | Sequence | 原作角色 |
|------|----------|----------|
| BlizParticle01 | Attack - 1 | 杖尖金橙火花（Head，`frame_flags=1`） |
| BlizParticle02 | Spell、Stand Channel | 蓝焰 Head+Tail（`frame_flags=3`） |
| BlizPart_RidingDust | Walk | 马蹄尘，矩形盒 |

---

## 4. TeamGlow（已做，仍偏暗可调）

- 脚底：按三角法线拆贴地盘，`wc3_team_glow.gdshader`，`intensity=2.4`，`use_billboard=false`。
- 杖尖：MDX 多张平行面片改为单张 Quad + **同一 shader**，`intensity=3.6`，`use_billboard=true`（vertex 里相机朝向）。挂在 Weapon/Staff 的 `Tip` 下，局部 I。
- 旧路径曾用 `StandardMaterial3D` Additive 且 RGB **clamp 到 1**，HDR 加不亮；已弃。

调亮度只改 `MapModelCache._make_team_glow_shader_material` 的 intensity，或 shader 默认值。

---

## 5. 还没做 / 只做了近似（优先从上看）

1. **真正的 Tail**：WC3 按速度拉条带 + `TailUVAnim` / `TailDecayUVAnim`。现在是拉长 Quad + `align_y`，Spell 焰仍不像最终版。
2. **Head 与 Tail 同时画**：原作 `Both` 是两套图元；我们合成一张。
3. **`emission_rate` 动画**：应驱动 GPUParticles 的 `amount_ratio` 或重启发射，而不是只 `emitting`。
4. **`decay_uv`**：寿命后半换格；Clouds8x8 现常钉在第 0 格。
5. **绑骨后的 `local_pivot`**：Particle01 Pivot 更靠杖身，Particle02 更靠尖。现两套都钉在 Weapon Tip（普攻对齐优先）。
6. **FilterMode** 全表（Modulate / AddAlpha / AlphaKey 等）。
7. **Speed / Latitude / Width / Gravity 动画轨**（sidecar 未写）。
8. **RibbonEmitter**、旧版 **ParticleEmitter**（非 2）。
9. **priority_plane** 绘制顺序。
10. **LineEmitter** 在零尺寸时无意义；有尺寸时的轴向与 WC3 是否一致未校对。
11. **灯光** 只做了节点搬家，衰减/队色未按 MDX Light 块还原。
12. Godot 硬编码：`flatness=0.15`、Additive 抬色/抬缩放——调参不是规格。

---

## 6. 相关代码与文档

| 路径 | 职责 |
|------|------|
| `tools/asset-convert/src/convert-mdx.js` → `writePe2Sidecar` | 写 pe2.json |
| `scripts/map/presentation/effects/wc3_pe2_particles.gd` | JSON → GPUParticles3D |
| `scripts/tool/wc3_scn_pe2.gd` | bake `:emitting` / 非绑骨 position |
| `scripts/tool/export_model_scenes.gd` | 调 PE2 + 挂点 Tip |
| `scripts/map/infra/map_model_cache.gd` | TeamGlow、绑骨 rest、运行时组场景 |
| `assets/shaders/wc3_team_glow.gdshader` | 脚底 + 杖尖 glow |
| `scripts/map/presentation/anim_playback.gd` | 切 Sequence 时 `apply_sequence` |
| `tests/unit/selftest_attachment_bake.gd` | ArchMage Tip / glow / Particle01 在 Tip 下 |
| `tests/integration/selftest_pe2_brazier.gd` | 火盆类全程发射 |

文档：

| 文档 | 关系 |
|------|------|
| [MDX_SKINNING_GODOT.md](MDX_SKINNING_GODOT.md) | Tip 局部 = Pivot 厘米；粒子跟网格同一蒙皮空间 |
| [ATTACHMENTS_BAKE.md](ATTACHMENTS_BAKE.md) | 挂点拼装总方案；PE2 细节以本文为准 |
| [../architecture/SCRIPTS_LAYOUT.md](../architecture/SCRIPTS_LAYOUT.md) | `scripts/tool` 里 pe2 bake |
| [../../tools/asset-convert/README.md](../../tools/asset-convert/README.md) | 转换步骤含 pe2.json |
| [04-wc3-effects-conversion.md](../blog/04-wc3-effects-conversion.md) | 对外说明（全貌，偏教程） |
| [../tools/ASSET_LAYOUT.md](../tools/ASSET_LAYOUT.md) | pe2.json / .scn 不入库 |
| [../shader/README.md](../shader/README.md) | 岸浪 PE2 是另一套（MultiMesh），不是单位 GPUParticles |
| [../roadmap/TODO.md](../roadmap/TODO.md) | visuals 封装 + PE2 历史条目 |

---

## 7. 校对时怎么看

1. 普攻 → Particle01 + 杖尖 TeamGlow，应对齐网格杖尖。  
2. Spell / Stand Channel → Particle02（不要在 Attack 里找蓝焰）。  
3. Walk → 马蹄尘。  
4. 强度不对先改 glow `intensity`；形状不对再改 Tail / rate 轨（§5）。
