# 特效烘焙与验收（2026-09-13）

`.scn` 保存可运行的模型、材质与发射器；不保存一次粒子模拟的画面。质量修正必须进入转换数据、Godot 映射或独立的模型配置，并验证重新加载后的场景。

## 当前实现

- Ribbon 的寿命、发射率、宽度、颜色是保存属性；磁盘重载保留配置。
- 转换器输出 `*.ribbon.json`，包含序列、可见性关键帧、父层级运动采样（30 Hz）。此前仅有 Ribbon 消费端，常规转换未输出这个文件。
- PE2 按 ModelSpace 标志选择模拟空间。世界空间的速度和发射位置由 Godot emission transform 换算，尺寸与重力由发射器脚本换算，避免重复或遗漏 0.01 缩放。当前针对项目的均匀缩放模型。
- PE2 Blend / Additive / Modulate / Modulate2x / AlphaKey 分开映射。以当前依赖 war3-model 的 PE2 renderer 为参照：AlphaKey 为 alpha 阈值 0.83 的加法混合；PE2 枚举与模型材质 Layer 枚举不同。
- GPU 顶点 shader 按粒子年龄选择 life/decay 阶段、行列、帧区间和重复次数；Head+Tail 使用两个 draw pass，分别读取 head/tail 图集参数。
- 连续发射固定容量，以 `amount_ratio` 表达密度；原始 Linear / Hermite / Bezier 发射率在 bake 时采样为 60 Hz 数值轨，保留原关键帧。旧 sidecar 未记录插值类型时按阶梯轨兼容，需重新转换获得新字段。
- Squirt 的正发射量关键帧生成 `emit_burst(count)` 方法轨，停止连续发射，不用 restart 清除已有粒子。需要 Forward+ / Mobile 的手动 GPU 发射能力；项目使用 Forward+。
- 去掉通用粒子的额外提亮、尺寸放大与尾迹增量启发式；排序读取 SortFarZ 与 priority plane。
- 增量 bake 使用内容签名：模型、gltf 外部 buffer/image、同模型 JSON、JSON 贴图、模型配置、相关脚本与 shader、Godot 版本。删除依赖或同秒修改内容也会重烘焙。旁边的 `*.scn.bake.json` 仅在成功保存后记录，旧场景没有清单时首次重烘焙。

## 单模型美术配置

配置放在 `assets/fx-overrides/<模型逻辑路径去扩展名>.json`，与生成目录分离，可提交，不会被重新转换覆盖。例如 `assets/fx-overrides/Abilities/Weapons/FireBallMissile/FireBallMissile.json`：

```json
{
  "emitters": {
    "实际发射器名称": {
      "size_multiplier": 1.0,
      "rate_multiplier": 1.0,
      "color_multiplier": 1.0
    }
  }
}
```

发射器名称取自该模型 `pe2.json`。可选 `local_coords` 布尔值覆盖 ModelSpace；省略时遵循原模型。三个倍率默认均为 1。调整前先校对原作的轮廓、运动和时序，再调整明暗。原有 visuals 覆盖场景仍优先于基座 `.scn`，验收时须确认加载的是刚烘焙的基座。

## 重建与验证

仓库根目录执行（以水元素为例）：

```powershell
node tools/asset-convert/src/cli.js --models-only --skip-clean --skip-passthrough --skip-scn --force --include 'Units/Human/WaterElemental/**'
npm --prefix tools/asset-convert run bake:scn -- --include Units/Human/WaterElemental/WaterElemental.gltf
```

没有原始 MDX 时，仍可仅 bake 现有 sidecar，但不能凭空恢复缺失字段。

- `tests/unit/selftest_fx_bake_fidelity.gd`：场景磁盘重载、模拟空间、混合配置、发射率实际动画求值、burst 关键帧、内容依赖失效。
- `tools/asset-convert/src/ribbon_export.test.mjs`：Ribbon 导出包含父节点运动、显隐时间、零 alpha；直接用 Node 执行。
- `tests/integration/review_fx_bake.gd`：必须使用真实渲染器，不加 `--headless`。加载主城、水元素、火球和火盆 `.scn`，固定种子、相机、背景与时间步，结果写到 `.godot/fx-review/`。以 `--fixed-fps 60` 运行，图片名中的 020/060/120 是模拟帧编号。

Headless 检查不证明 GPU 画面正确；截图验证也不等于原作保真验收。正式验收需加入相同动作、时间点、机位的原作参考。

本轮验证：主城、水元素、火球、火盆 4 个 `.scn` 重烘焙成功；重复执行得到 `exported=0 skipped=4 failed=0`。新增保真测试、Ribbon 导出测试、现有水元素常驻粒子／火盆测试，以及 Global Sequence／Morph 转换回归均通过。D3D12 Forward+ 实际渲染完成 18 张截图（额外覆盖水元素 Attack 与火球 Death），未发现脚本解析或 shader 编译错误。沙箱日志仍有系统证书读取和着色器缓存写入提示，画面输出成功。火盆使用现有 sidecar，本机 staging 没有它的原始 MDX。

## 仍有边界

- PE2 Tail 几何仍是沿速度对齐的拉长 quad，尚非原作完整的速度／历史长度算法。
- PE2 Speed / Gravity / Width 等动画参数尚未完整保留；粒子 Global Sequence 独立时钟未全面实现。
- Ribbon 的高度／颜色／材质层动画、非加法材质与复杂局部姿态仍未完整映射。
- 粒子容量上限为 4096；极端爆发、短循环重叠及非均匀缩放需专门调优。跨透明物体的排序仍受 Godot 限制。
- 现有某些技能还叠加 `Wc3FxPresenter` 等美术处理，本轮不承诺全部技能自动达到原作一致效果。
