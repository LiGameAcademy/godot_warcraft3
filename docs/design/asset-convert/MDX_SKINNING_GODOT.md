# MDX → Godot 蒙皮与挂点（复盘）

> **层**：资源映射（`tools/asset-convert`）+ 表现烘焙（`export_model_scenes` / `MapModelCache`）。  
> **对照模型**：`Units/Human/HeroArchMage`（骑士 T-pose 顶点 + 马已是绑定外形）。  
> **最后更新**：2026-08-19

---

## 1. 结论（先看这个）

Godot 导入 skinned glTF 时，关节节点的 TRS **经常进不了** `Skeleton3D` rest；蒙皮公式与 WC3 也不自动对齐。本仓库当前稳定组合：

| 量 | 取值 | 原因 |
| ---- | ------ | ------ |
| 顶点 | MDX 模型空间（只做 Y-up，**不** ×0.01） | 根节点 `scale=0.01` 才变米 |
| IBM | 单位阵 | `IBM=inv(bind)` + rest 丢失 → 网格吸到原点 |
| 骨骼 rest / 默认 pose | **Stand 第 0 帧的世界阵**（`*.bone_rest.json` v2） | 马顶点已是站姿（阵≈I）；骑士是 T-pose，要靠这层坐下 |
| 动画轨 | **绝对世界阵** `transformMat4Wc3ToGltf(world)` | Godot 4.6 平铺骨上 `global_pose≈pose`；写成 `world*inv(Stand)` 一播动画手臂打回 T-pose |
| 绑骨挂点 Tip | `pivot_meters / 0.01` | BA 在骨原点；IBM=I 时与蒙皮杖尖一起转 |

**禁止再试（已验证会坏网格）：**

1. `IBM = inv(Pivot 链)` 而 rest 仍是单位阵 → 人马堆成一团（碰撞不走蒙皮所以还站着）。
2. 关节 `setTranslation(Pivot差)` + IBM=I + 模型空间顶点 → 蒙皮加第二遍平移，骑士嵌进马身。
3. sidecar 里 **同时** `set_bone_rest` 和 `set_bone_pose_position` 同一平移 → rest×pose 叠两次。
4. 动画轨 `localT - Pivot差`：Stand 第 0 帧世界平移本是 0，减完变成 `-pivot`，绕原点转。
5. 动画轨 `world * inv(Stand)`：默认还能靠 rest/pose=Stand 坐下，**一播放** pose 被写成 I，手臂 T-pose。
6. 用改 IBM / 改 pose 去「拧」杖尖挂点 → 网格再次坏掉。挂点只动 BoneAttachment **子节点**。

权威烤本：`assets/asset-converted/.../*.scn`。编辑器预览可拷到 `tmp/...`（gitignore）；不要打开平铺的 `tmp/Units/Human/HeroArchMage.scn`。

---

## 2. 空间与公式

- WC3 节点局部：`T(pivot)·R·S·T(-pivot)·T(anim)`（`mat4FromRotationTranslationScaleOrigin`）。
- 根节点 `0.01`：顶点/骨骼/挂点骨局部都是厘米；`attachments.json` 的 `pivot`、相机、碰撞已 ×0.01（米），挂**场景根**。
- 蒙皮（IBM=I）：`v' = bone_global * v`。骨全局必须是该帧 WC3 世界阵（glTF 轴）。
- Godot 4.6 + **平铺骨骼**（`parent=-1`）：实测 `get_bone_global_pose().origin` 跟 pose 走，不跟 rest 走。因此：
  - 打开场景：`set_bone_rest(Stand世界)` 后 **`reset_bone_pose`**，把 pose 拷成绑定阵，默认能看见坐姿。
  - AnimationPlayer：轨必须写同一套世界阵，播 Stand 第 0 帧 pose 仍是绑定阵。

`*.bone_rest.json` v2 字段：`name`, `translation`, `rotation` `[x,y,z,w]`, `scale`。由 Stand（无名则 Sequences[0]）第 0 帧世界阵分解得到。

---

## 3. 挂点

`BoneAttachment3D` 每帧被写成骨原点。杖尖 / Weapon Ref 的 MDX Pivot `P` 一般不是原点。

子节点 `Tip` 的骨局部（与蒙皮相同：`v' = bone_global × v_model`）：

```text
Tip.local = pivot_meters / 0.01
```

不要用 `inv(bind) × P`：那会把插座钉在未蒙皮的 Pivot 上，攻击时网格杖尖已经 `M × v`，特效会漂在旁边。

`pivot_delta` 只作 sidecar 调试，不要当 Tip 位移。

- 脚底 Origin / OverHead：继续挂场景根，用已 ×0.01 的 `pivot`。
- 杖尖 TeamGlow / 同骨 PE2（如 `BlizParticle01`）：挂到 `Tip` 下，局部 Transform 为单位阵。

---

## 4. 编辑器打开哪份

| 路径 | 用途 |
|------|------|
| `assets/asset-converted/Units/Human/HeroArchMage/HeroArchMage.scn` | 管线产物 |
| `tmp/Units/Human/HeroArchMage/HeroArchMage.scn` | 同目录拷贝，方便打开 |
| `tmp/Units/Human/HeroArchMage.scn` | 旧平铺拷贝，作废 |

关掉场景再开；Godot 会缓存 `.scn`。`Wc3ModelScene`（`@tool`）进树会再套一次 sidecar，防止 packed rest 丢失。

重转单模型：

```text
cd tools/asset-convert
node src/cli.js --models-only --force --include "Units/Human/HeroArchMage/**"
```

---

## 5. 相关代码

| 文件 | 职责 |
|------|------|
| `tools/asset-convert/src/convert-mdx.js` | 顶点/IBM/动画世界阵 / `writeBoneRestSidecar` |
| `scripts/map/infra/map_model_cache.gd` | `apply_bone_rest_sidecar`、TeamGlow 杖尖 |
| `scripts/tool/export_model_scenes.gd` | 先 rest 再拼装 BA+Tip |
| `scripts/presentation/wc3_model/wc3_model_scene.gd` | 编辑器/运行时套 rest |

小件清单仍见 [ATTACHMENTS_BAKE.md](ATTACHMENTS_BAKE.md)。粒子 / TeamGlow 映射见 [PE2_GODOT.md](PE2_GODOT.md)。
