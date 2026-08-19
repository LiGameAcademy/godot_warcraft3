# 小件 / 特效烘焙拼装方案（m2g attachments.json + export_model_scenes 拼装 + AnimationPlayer 统一管理）

> **关联 commit**：C-1（extract_attachments + write_attachments_sidecar + selftest 5/5）→ C-2（export_model_scenes 拼装 + selftest 5/5）→ C-3（AnimationPlayer 合并 + selftest 5/5）
> **关联代码**：`tools/asset-convert/src/convert-mdx.js` + `tools/asset-convert/src/cli.js` + `scripts/tool/export_model_scenes.gd` + `tests/unit/selftest_attachments.gd` + `selftest_attachment_bake.gd` + `selftest_animation_merge.gd`
> **触发问题**：TownHall .scn 实际只有 35 个 MeshInstance3D，缺 15 面旗子 + 4 时针 + 4 分针 + 2 铃铛 + 1 平面（Skeletal Mesh 全有，BoneAttachment 全丢）；Footman 缺 26 个 box / cantine / gutz 装饰物；所有 200+ WC3 模型都受影响
> **最后更新**：2026-08-19（蒙皮/挂点复盘见 [MDX_SKINNING_GODOT.md](MDX_SKINNING_GODOT.md)；粒子/TeamGlow 映射见 [PE2_GODOT.md](PE2_GODOT.md)）

---

## TL;DR

WC3 模型 = 大件（geoset mesh，~35 个）+ 小件（Helper 节点绑骨，旗子/时钟/铃铛/装饰物，~30 个）+ 特效（粒子/光/拖尾）。m2g 只导大件，**小件 + 特效在 .gltf 里空壳**——`export_model_scenes.gd` 烤 .scn 时丢。

3 层方案：
1. **m2g 同步导 `attachments.json` sidecar**：记录每个小件/特效的类型、骨绑定、mesh/PE2 源、transform、可选动画轨
2. **`export_model_scenes.gd` 烘焙 .scn 时拼装**：加载 JSON + 遍历 attachment → 创建 `BoneAttachment3D` + 子节点（MeshInstance3D / GPUParticles3D）→ 挂到 skeleton
3. **AnimationPlayer 统一管理**：attachment 动画轨**合并**到**主** AnimationPlayer（运行时 1 个 AnimationPlayer 控全模型）

3 个 commit 实施，每步有 5/5 selftest 守门。

---

## 1. 背景：WC3 模型结构 + m2g 当前缺口

### 1.1 WC3 MDX 模型结构

WC3 一个模型（.mdx）由 3 类元素组成（war3-model 库 `parseMDX` 解析后）：

| 类型 | 模型字段 | 数量（TownHall）| 作用 |
|------|----------|----------------|------|
| **Geoset**（大件）| `model.Geosets` | 35 | 独立 mesh group：城墙 / 屋顶 / 装饰几何等；可独立隐藏/动画 |
| **Bone**（骨骼）| `model.Bones` | 47 | Skeleton3D bones，控制 geoset 顶点变形 |
| **Helper / Particle / Light / Ribbon**（小件/特效）| `model.Nodes[*]`（Type=Helper/ParticleEmitter2/Light/RibbonEmitter 等） | ~26 | 绑到 bone 的"附加元素"：旗子 / 时钟 / 铃铛 / 烟雾 / 火光 / 拖尾 |

**关键关系**：
- Helper 通过 `Bone` 引用绑定（`Node.Parent = Bone.ObjectId`）
- Helper 通过 `GeosetId` 引用 mesh 数据（"我显示 Geoset_10"）
- Particle 通过 `Bone` 引用绑定，参数在 ParticleEmitter2 里
- **Helper 自身**只含 `transform + bone reference + geoset reference`，**没有 mesh 数据**

### 1.2 m2g 当前行为

`tools/asset-convert/src/convert-mdx.js` 处理 Geoset + Bone + 主 mesh，**不**为 Helper/Particle/Light/Ribbon 建 GLTF node：

- ✅ Bone → 47 个 GLTF nodes（skeleton）
- ✅ Geoset → 35 个 MeshInstance3D
- ❌ Helper（旗子/时钟/铃铛/平面）→ .gltf 84 个 nodes 里有 26 个**空壳**（只有 `name` 没 mesh / 没 children / 没 skin）
- ❌ Particle / Light / Ribbon → 同上

### 1.3 实测 TownHall .scn

`export_model_scenes.gd` 烤的 .scn instantiate 后：

```
Buildings_Human_TownHall_TownHall_mdx (Node3D, root)
├── TownHall (Node3D)
│   └── Armature (Node3D)
│       └── Skeleton3D (47 bones)
│           ├── Geoset_0..35 (35 MeshInstance3D, mesh=true)  ← 全有
│           ├── ❌ 缺 Plane01 / ClockHand Minute01-04 / Hour01-04 / Upgrade1 Bell / Bell01 / Flag48-62
└── AnimationPlayer
```

**缺 12+ 个 BoneAttachment 节点**。旗子光秃秃、时钟没指针、铃铛丢。

Footman 同样缺 26 个 box / cantine / gutz 装饰物。

**所有 200+ WC3 模型都受影响**（m2g 通用 bug）。

---

## 2. 设计口径

3 个原则：
1. **解耦**：mesh 数据（小件/特效本体）放 `assets/asset-converted/`，结构化元数据放 `attachments.json`（**不在 .gltf 里**，避免 .gltf 越来越大）
2. **单 AnimationPlayer**：所有动画（小件顶点变形 / 粒子参数 / 骨骼旋转 / 主 mesh 顶点变形）合并到 1 个 AnimationPlayer，运行时 1 个 set_animation 控全
3. **复用 geoset mesh**：小件不复制 mesh 数据，引用同模型 geoset（如 15 面旗子共享 Geoset_10 mesh，顶点权重绑到不同 bone）

**WC3 复刻**：旗布飘动 = mesh 顶点变形（Geoset_10 的 anim）；铃铛光晕 = 粒子（ParticleEmitter2）；时钟 = 骨骼旋转（已有）。

**不做**：
- ❌ GLTF KHR_node_visibility（Godot 4 不支持 .scn 烤 bake）
- ❌ Skin 多 mesh 共享（GLTF spec 不支持 skin 跨 mesh）
- ❌ Boids / RVO / flow（老李原话，与本设计无关，但记入"明确不做"）

---

## 3. JSON Schema：`.attachments.json`

### 3.1 文件位置

`assets/asset-converted/<model_path>/<model>.attachments.json`

例：`assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json`

### 3.2 顶层结构

```json
{
  "version": 1,
  "model": "Buildings/Human/TownHall/TownHall.mdx",
  "skeleton_bone_count": 47,
  "attachments": [
    { ... },
    { ... }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `version` | int | schema 版本（=1） |
| `model` | string | 源 MDX logical path（debug 用） |
| `skeleton_bone_count` | int | skeleton bones 数（校验用） |
| `attachments` | array | attachment 列表 |

### 3.3 attachment 字段

```json
{
  "name": "Flag48",
  "type": "mesh",
  "bone": "Flag48",
  "source": "Geoset_10",
  "transform": {
    "pos": [0.0, 0.0, 0.0],
    "rot": [0.0, 0.0, 0.0, 1.0],
    "scale": [1.0, 1.0, 1.0]
  },
  "visibility_default": true,
  "animations": [...]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✅ | 节点名（与 .gltf empty node 名一致） |
| `type` | enum | ✅ | `mesh` / `particle` / `light` / `ribbon` |
| `bone` | string | ✅ | Skeleton3D bone 名（必须存在） |
| `source` | string | ✅ | mesh: `Geoset_<id>` / particle: `pe2:<pe2_id>` / light: `<light_param_id>` |
| `transform` | object | ❌ | 局部 TRS（相对 bone）；缺省 identity |
| `visibility_default` | bool | ❌ | 默认可见性（=true） |
| `animations` | array | ❌ | 此 attachment 专属动画轨（合并到主 AnimationPlayer） |

### 3.4 animations 字段（attachment 专属）

```json
{
  "track_path": "BoneAttachment3D:Flag48:MeshInstance3D",
  "track_property": "visible",
  "keyframes": [
    { "time": 0.0, "value": true },
    { "time": 1.5, "value": false }
  ]
}
```

实际动画轨细节在 commit C-3 设计（AnimationPlayer 合并阶段）。

### 3.5 type-specific 字段

**type=particle**（如旗子飘动的烟雾）：
```json
{
  "name": "SmokeFlag48",
  "type": "particle",
  "bone": "Flag48",
  "source": "pe2:flag_smoke",          // PE2 预制名
  "transform": { "pos": [0, 0, 0], ... },
  "pe2_settings": {                    // PE2 粒子参数（透传 PE2 预制）
    "emission_rate": 5.0,
    "lifetime": 2.0,
    "color_start": [1, 1, 1, 1],
    "color_end": [1, 1, 1, 0]
  },
  "animations": [...]
}
```

**type=light**：
```json
{
  "name": "BellGlow",
  "type": "light",
  "bone": "Upgrade1 Bell",
  "source": "OmniLight",
  "transform": {...},
  "light_settings": {
    "color": [1.0, 0.8, 0.3],
    "energy": 2.0,
    "range": 8.0
  }
}
```

**type=ribbon**（拖尾）：
```json
{
  "name": "FlagRibbon",
  "type": "ribbon",
  "bone": "Flag48",
  "source": "ribbon_emitter",
  "ribbon_settings": { ... }
}
```

---

## 4. m2g 改造（C-1 commit）

### 4.1 新增函数（`convert-mdx.js`）

```js
/**
 * 从 model 提取 attachments（小件/特效清单）
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @returns {object} attachments JSON 对象
 */
export function extractAttachments(model, logicalPath) {
  const out = {
    version: 1,
    model: logicalPath,
    skeleton_bone_count: (model.Bones ?? []).length,
    attachments: []
  };
  for (const node of model.Nodes ?? []) {
    const type = node.Type ?? node.type;
    if (type === "Helper") {
      // 旗子 / 时钟 / 铃铛 / 平面 / cantine / box 等
      out.attachments.push({
        name: node.Name,
        type: "mesh",
        bone: getBoneNameById(model, node.Parent ?? -1),
        source: `Geoset_${node.GeosetId ?? 0}`,
        transform: extractTransform(node),
        visibility_default: true,  // 无 Visibility 轨则可见；Flags 0x4 是 DontInherit Scaling
        animations: extractAnimations(node, model)
      });
    } else if (type === "ParticleEmitter2") {
      out.attachments.push({
        name: node.Name,
        type: "particle",
        bone: getBoneNameById(model, node.Parent ?? -1),
        source: `pe2:${node.ParticleEmission ?? node.ObjectId}`,
        transform: extractTransform(node),
        pe2_settings: extractPe2Settings(node),
        animations: extractAnimations(node, model)
      });
    } else if (type === "Light") {
      // ...
    } else if (type === "RibbonEmitter") {
      // ...
    }
  }
  return out;
}


/** 写 attachments JSON sidecar */
export function writeAttachmentsSidecar(model, logicalPath, outDir) {
  const att = extractAttachments(model, logicalPath);
  const logical = mdxLogicalToAttachments(logicalPath);  // <model>.attachments.json
  const dest = path.join(outDir, ...logical.split("/"));
  atomicWriteBytesSync(dest, `${JSON.stringify(att, null, 2)}\n`);
  return dest;
}
```

### 4.2 cli.js 集成

```js
// 写 .gltf + .bin 之后，再写 .attachments.json
await new NodeIO().write(dest, document);
unlinkQuiet(dest.replace(/\.gltf$/i, ".glb"));
writeAttachmentsSidecar(model, logicalPath, outDir);
```

### 4.3 paths.js 路径

```js
export function mdxLogicalToAttachments(logicalPath) {
  const gltf = mdxLogicalToGltf(logicalPath);
  if (gltf.toLowerCase().endsWith(".gltf")) {
    return `${gltf.slice(0, -5)}.attachments.json`;
  }
  return `${gltf}.attachments.json`;
}
```

---

## 5. `export_model_scenes.gd` 改造（C-2 commit）

### 5.1 加载 .attachments.json

`_collect_glb` 找 .gltf 时，**同时**读同名 `.attachments.json`：

```gdscript
var att_path := logical_gltf.replace(".gltf", ".attachments.json")
if FileAccess.file_exists(att_path):
    var att_text := FileAccess.get_file_as_string(att_path)
    var att := JSON.parse_string(att_text)
    # 拼装阶段
```

### 5.2 拼装流程

```gdscript
# 加载 .gltf 得到 root
var root: Node3D = cache.instance_gltf_preview(...)
if att != null:
    var skeleton := _find_skeleton(root)
    for item in att["attachments"]:
        var bone_idx := skeleton.find_bone(item["bone"])
        if bone_idx == -1:
            push_warning("attachment bone missing: %s" % item["bone"])
            continue
        var bone_attach := BoneAttachment3D.new()
        bone_attach.name = item["name"]
        bone_attach.bone_name = item["bone"]
        skeleton.add_child(bone_attach)
        bone_attach.global_transform = ...  # bone 的 transform
        # 创建子节点
        match item["type"]:
            "mesh":
                var mi := MeshInstance3D.new()
                mi.name = item["name"] + "_mesh"
                mi.mesh = _resolve_geoset_mesh(item["source"], cache)
                bone_attach.add_child(mi)
            "particle":
                var particles := GPUParticles3D.new()
                particles.name = item["name"] + "_particles"
                # 从 pe2 预制加载 / 用 pe2_settings 构造
                bone_attach.add_child(particles)
            # ... light / ribbon
```

### 5.3 AnimationPlayer 合并（C-3 commit）

```gdscript
# 收集所有 attachment 动画轨
var main_anim := root.get_node("AnimationPlayer")
for item in att["attachments"]:
    for anim_track in item.get("animations", []):
        var track = AnimTrack.new()
        track.path = anim_track["track_path"]
        # ... 加载 keyframes
        main_anim.add_animation("ATTACH_" + item["name"], animation)
        # 或合并到现有 animation
```

---

## 6. 决策矩阵

| 决策 | 选项 | 选 | 原因 |
|------|------|----|------|
| 小件数据存哪 | ① .gltf ② JSON sidecar ③ .pe2.json | ② | .gltf 不适合大量 metadata；.pe2.json 是粒子专用 |
| 复用 mesh 方式 | ① 复制顶点 ② .gltf 共享 ③ BoneAttachment + skin | ③ | Godot 4 BoneAttachment3D 原生支持；mesh 复用 geoset |
| 动画管理 | ① 每 attachment 独立 AnimationPlayer ② 统一 AnimationPlayer | ② | set_animation("Stand") 控全；运行时 1 个 player 简单 |
| 是否保留现有 35 个 MeshInstance3D（geoset）| ① 是 ② 否 | ① | geoset 仍是主 mesh；小件是附加 |
| PE2 粒子 | ① 单独 .pe2.tscn ② bake 进 .scn ③ 运行时 JSON | ② | 贴图内嵌，编辑器播 Sequence 即可见；不入库 tscn |
| bake 阶段 | ① .gltf bake 时 ② runtime load 时 | ① | 烤 .scn 后运行时无需再 load JSON；性能 + 简化 |
| GeometryInstance3D vs MeshInstance3D | ① MeshInstance3D ② GeometryInstance3D | ① | 简化；light/particle 各自类型 |
| 是否支持 Light / Ribbon | ① 是 ② 否（只 Mesh + Particle）| ① | WC3 铃铛光晕 = Light，旗拖尾 = Ribbon |
| 多 LOD（小件分级）| ① 不分 ② 分 | ① | 1.30+ WC3 不分；复刻 |
| 共享 mesh 跨模型 | ① 跨模型共享 ② 模型内共享 | ② | 跨模型 cache 太复杂；模型内共享够用 |

**4 个"明确不做"**：
- ❌ boids / RVO / flow（无关）
- ❌ GLTF KHR_node_visibility（Godot 4 .scn 不支持）
- ❌ Skin 跨 mesh 共享（GLTF spec 不支持）
- ❌ 多 LOD（1.30+ WC3 不分）

---

## 7. 测试契约

3 套 selftest 5/5 = 15 项守门：

### 7.1 `selftest_attachments.gd`（C-1）

- test_1: extractAttachments(TownHall) → >= 26 个 attachments（旗 15 + 钟 8 + 铃 2 + 平面 1）
- test_2: attachment 字段全（name / type / bone / source / transform）
- test_3: writeAttachmentsSidecar 写 .attachments.json 成功
- test_4: extractAttachments(Footman) → >= 26 个 attachments（box / cantine / gutz 等装饰）
- test_5: .attachments.json parse 回 attachments 数一致

### 7.2 `selftest_attachment_bake.gd`（C-2）

- test_1: bake TownHall → scn instantiate 后 Skeleton3D children 含 BoneAttachment3D
- test_2: BoneAttachment3D 的 bone_idx 对应 Skeleton3D bone
- test_3: BoneAttachment3D 子节点含 MeshInstance3D / GPUParticles3D
- test_4: bake Footman → scn 含 attachment 节点
- test_5: attachment name 匹配 .attachments.json

### 7.3 `selftest_animation_merge.gd`（C-3）

- test_1: bake TownHall → 1 个 AnimationPlayer（不增加）
- test_2: AnimationPlayer track 数 >= 主 mesh 轨 + attachment 动画轨
- test_3: track_path 引用 attachment 节点
- test_4: keyframe 时间 0..N 完整
- test_5: set_animation("Stand") 不报错

---

## 8. 实施分期

### C-1：m2g attachments 提取 + 写 sidecar
- `convert-mdx.js`：加 `extractAttachments` + `writeAttachmentsSidecar`
- `cli.js`：集成导出
- `paths.js`：加 `mdxLogicalToAttachments`
- `selftest_attachments.gd` 5/5
- 跑 Footman + TownHall 验 .attachments.json 写出

### C-2：export_model_scenes.gd 拼装
- `_collect_glb` 改：扫 .gltf 时**同时**读 .attachments.json
- bake 阶段：遍历 attachment → 创建 BoneAttachment3D + 子节点
- `selftest_attachment_bake.gd` 5/5
- 跑 Footman + TownHall 验 .scn 含 attachment

### C-3：AnimationPlayer 统一管理
- bake 阶段：收集 attachment 动画 → 合并到主 AnimationPlayer
- `selftest_animation_merge.gd` 5/5
- 端到端：TownHall 启 game 跑 → 旗飘 / 钟转 / 铃摇

---

## 9. 风险

| 风险 | 严重度 | 缓解 |
|------|--------|------|
| war3-model 库 `Node.Type` 字段名差异 | 中 | m2g 写时 `node.Type ?? node.type` 兼容；C-1 selftest 全 200+ 模型扫一遍 |
| Bone name 在不同模型重复 | 低 | BoneAttachment3D 用 bone_name 字符串找，加 `find_bone` 校验 |
| attachment 动画轨格式 wc3 复杂（TrackType / InterpolationType）| 中 | C-3 阶段先支持 visibility + position + rotation 3 种基础；复杂动画留后期 |
| Particle PE2 预制不齐全 | 中 | pe2_settings 兜底：缺预制时用 settings 构造 GPUParticles3D |
| GLB / .gltf / .pe2.json / .attachments.json 4 个文件同步 | 低 | m2g 一次性写齐；bake 阶段读 .attachments.json 找不到时 fallback |
| 大模型 attachment 数 200+ | 低 | BoneAttachment3D 1 个/attachment 性能 OK（WC3 真实模型都 < 50 attachment） |

---

## 10. 明确不做（6 ❌）

1. ❌ boids / RVO / flow（无关）
2. ❌ GLTF KHR_node_visibility（Godot 4 .scn 不支持）
3. ❌ Skin 跨 mesh 共享（GLTF spec 不支持）
4. ❌ 多 LOD（1.30+ WC3 不分）
5. ❌ m2g 内置 .gltf 节点方案（必须 JSON sidecar 解耦；.gltf 大了 Godot 4 烤 .scn 慢）
6. ❌ 运行时拼装（必须 bake 阶段拼装；runtime 找不到 .attachments.json）

---

## 11. 引用

- **F-PATH 寻路索引**：`docs/design/pathing/PATHING_INDEX.md`
- **SCN_COVERAGE baseline**：`docs/design/asset-convert/SCN_COVERAGE.md`
- **D3 决策（资源不入 git）**：`docs/data/PIPELINE.md` §3
- **HivEWE 模型结构参考**：`_ref/HiveWE/src/mdx/`（`MdxNode.cs` / `MdxParticleEmitter.cs` / `MdxHelper.cs`）
- **关键 commit**：
  - 1f012ac refactor(asset-convert): .glb → .gltf 切流
  - 4588d5e refactor(tools): 三车道契约代码落地
- **C-1 关联**：`docs/design/asset-convert/ATTACHMENTS_BAKE.md`（本文件）+ commit `feat(asset-convert): extractAttachments + writeAttachmentsSidecar + 5/5 selftest`

---

最后更新：2026-08-11
