# 开发地图资产引用清单

此清单用于确定新管线迁移范围，当前是可追溯的静态清单，不是已验收的游戏发布清单。默认按共享配置选择基础表；`--definition-profile candidates` 才扫描全部覆盖层候选。详见 [覆盖规则](DEFINITION_LAYERS.md)。

## 生成

```powershell
node tools/asset-convert/src/development-manifest-cli.mjs
node tools/asset-convert/src/development-manifest.test.mjs
```

手动验收引用扫描时，直接运行上面的扫描命令即可，`--worker-result` 不是必填参数。只有需要核对某次模型编译证据时才追加它，并传入实际存在的结果文件路径（带空格的路径用引号包围，不要输入尖括号占位符）。

本机 2026-09-29 已确认存在的 Footman 编译记录可这样使用；这是本地临时产物，其他机器或清理缓存后需使用重新编译生成的路径：

```powershell
node tools/asset-convert/src/development-manifest-cli.mjs --worker-result "tools/asset-convert/tmp/worker-UtoSMh/success-result.json"
```

默认读取 `assets/map-parsed/echoisles`、`assets/slk-exported` 和 `.cache/wc3-assets`，以 `hpea,htow` 作为人族开局补充种子。种子依据 `MeleeRacePreview` 的人族配置；更改种族／开局配置时需显式传入 `--seeds`。支持 `--map`、`--definitions`、`--source`、`--out`。`--worker-result` 可重复，但同一资产有多份匹配证据时标记歧义，不擅自挑选成功记录。

输出默认位于忽略目录 `tools/asset-convert/tmp/development-manifest/echoisles.json`。较小的 `assets/.staging/wc3-assets` 可用于测试，但不能据此判断完整解包库缺失。

## 当前覆盖

- 地图单位、装饰物及其放置变体；开始点 `sloc` 作为地图标记处理。
- 人族开局种子及定义表中的建造、训练、升级、出售、技能、Buff／Effect 引用。
- Buff 定义优先使用配置目录中的 `Units/AbilityBuffData.json`；缺少时直接解析源目录的 `Units/AbilityBuffData.slk`，记录原文件哈希。两者都不存在时报告 `missing_definitions`，补齐工具会按精确路径提取 SLK。损坏的表会报错，不按空表处理。
- Func 表按 `configuration.definition_profile` 合并；`candidates` 模式读取全部五层并保留候选。字段键忽略大小写、对象 ID 区分大小写，后层覆盖前层，显式空值清空。`definition_conflicts` 保存覆盖历史，包括同文件重复字段，只输出可达对象的差异。
- 已知对象 ID 的技能 Data 字段引用，保守纳入候选，包括可能召唤的单位。
- 定义表明确写出的模型和纹理路径；MDL 引用可解析到磁盘上的 MDX，忽略路径大小写。
- Func 的空行和整行注释不产生引用。`Art`／`Casterupgradeart` 图标的 `.tga` 引用优先找原路径，缺少时尝试同名 `.blp`，保留原请求与候选；不把此规则应用于寻路纹理。
- 模型内部纹理、当前已知可替换纹理默认值、第一代粒子引用的模型路径。
- 每项记录引用对象、表名、字段、请求路径和候选路径；输入表与源资产带 SHA-256。

## 状态解释

`available` 只代表选定源目录存在相应文件。`source_missing` 和 `source_invalid` 分别表示源文件缺失和解析失败，不能从这些状态推断旧游戏缓存是否可用。

模型未提交编译证据时为 `uncompiled`。新 worker 输出 `source_sha256`、`output_sha256` 和输出绝对路径；清单检查源哈希及当前输出文件哈希，匹配后仍只标记 `compiled_partial`，保留各编译组件结果和全部诊断。不匹配、旧报告缺签名或输出被修改时为 `stale_or_unverifiable`。编译规则及依赖版本尚未检查，字段明确写为 `compiler_version=unchecked`、`dependency_versions=unchecked`，不能作为发布缓存命中依据。

`fallback` 表示编译诊断中存在 pending／fallback／missing 项。材质／骨架计数不会被转换成视觉通过。`visual`、`game` 均保持 `unverified`，`deliverable=false`。

## 未闭合范围

当前 `coverage.complete=false`，仍需核对运行时对象覆盖、不同 Func 表覆盖顺序、动态脚本生成、随机掉落、地图自定义对象、地形、水、完整 UI／音频／肖像和所有玩家颜色变体。版本候选目前按 TFT 优先，需与运行时实际内容版本配置对齐。清单会保守纳入酒馆可售英雄及其技能，因此候选范围大于地图开局实际显示的范围。

2026-09-28 本地完整解包目录的初步扫描得到 334 个对象、276 个模型、498 个纹理候选，41 项在该目录中找不到，17 条对象关系未解析。缺失集中于炼金术士、修补匠、火焰领主相关资源等；这是当前解包内容与定义表版本需要核对的线索，不等于这些资源在玩家原版安装中必然不存在。

后续先收口上述覆盖规则及缺失来源，再将明确的投射物、光晕和 Ribbon 候选作为编译样本；不能把此次静态扫描当成完整依赖闭包。

## 从原版档案补齐缺失源文件

```powershell
node tools/asset-convert/src/development-recovery-cli.mjs --game-dir "D:/Program Files (x86)/Warcraft3"
```

此命令是开发阶段的可写导入工具，不属于只读资产查看器。默认只向 `.cache/wc3-assets` 补充清单中缺失的源文件；按原有 MPQ 优先级解包，同一路径后包覆盖前包。模型路径同时探测 MDX／MDL，精确路径不依赖 MPQ 的文件列表。已经存在的资产不会因此全量刷新，旧缓存的版本一致性仍需单独核验。

每轮重新扫描，以补齐新模型引入的纹理和粒子模型依赖；同一次运行不重复尝试找不到的路径，最多 8 轮。解包错误、剩余缺失或达到轮数上限均返回非零退出码，并写入报告。`sources_available` 仅表示当前静态候选清单没有缺失源文件，不表示解析、编译、视觉验收或完整范围已经通过。

默认审计报告为 `tools/asset-convert/tmp/development-manifest/recovery.json`，其中 `manifest` 是重新扫描后的清单，`passes` 保存每轮请求、解包统计和恢复的资产身份。独立的 `.cache/development-extraction-manifest.json` 保存恢复文件的最终来源包、大小与哈希，不覆盖已有全量解包清单。支持 `--map`、`--definitions`、`--source`、`--seeds`、`--worker-result`、`--out` 和 `--extraction-manifest`。

缺失定义表也会进入每轮 `requested`。`recovered` 只列资产身份；定义表恢复结果查看重扫后的 `missing_definitions` 以及解包来源清单。

本机核查发现原先 41 项缺失资源全部存在于 `War3Patch.mpq`，而该包的文件列表仅有 2 条，且不列出炼金术士模型。这确认至少这批缺失是缓存解包不全，不能归因于转换器或原版安装缺少资产。

2026-09-28 实测两轮分别恢复 41 和 18 个文件，解包错误为 0；新清单为 334 个对象、276 个模型、521 个纹理候选，源缺失与模型解析失败均为 0。第二次运行无需解包（0 轮）。17 条 Buff／Effect 关系仍未解析，定义覆盖规则和完整范围仍待收口；这些数字只描述当前候选范围。

2026-09-29 补入原版 Buff 表及覆盖层候选后，17 条引用已全部解析。当前本机结果为 347 个对象、276 个模型、527 个纹理候选，源缺失、定义表缺失、未解析引用均为 0；记录 211 处定义差异。新增定义表来源为 `War3Patch.mpq`。完整范围仍未闭合，后续需让各运行时目录读取器统一采用明确的覆盖策略，并核对动态生成与脚本 fallback。

## 本轮手动验收

在仓库根目录打开 PowerShell。需要已安装项目开发工具依赖和本机原版 MPQ；本轮验收不需要打开 Godot。资产查看器尚未接入此清单格式，因此不要用“打开其他报告”来加载该 JSON。

1. 运行只读扫描：

   ```powershell
   node tools/asset-convert/src/development-manifest-cli.mjs
   $report = Get-Content tools/asset-convert/tmp/development-manifest/echoisles.json -Raw | ConvertFrom-Json
   $report.summary
   $report.coverage.complete
   ```

   当前默认 `base` 本机预期：`objects=339`、`models=275`、`textures=519`，三个缺失／未解析计数均为 0，`definition_conflicts=1`，`coverage.complete=False`。唯一差异为基础文件内 `nogm` 的重复 `Buttonpos`。更换配置、原版版本、定义表或地图后数量可以变化，不应为了匹配数量删掉引用。

2. 核查 Buff 来源和冲突可追溯性：

   ```powershell
   $report.objects | Where-Object { $_.id -in @('BHbz','Blsa','BNrf','BNst','BNva') } | ConvertTo-Json -Depth 5
   $report.inputs | Where-Object { $_.path -match 'AbilityBuffData' }
   $report.definition_conflicts | Select-Object -First 3 | ConvertTo-Json -Depth 5
   ```

   预期：五个 ID 都存在，原因可以追到技能的 Buff 字段；定义输入有路径和 SHA-256；冲突包含对象、字段、双方来源和值。五个 Func／Strings 目录现已使用共享规则，但运行时 mod、动态脚本引用及 SLK 版本仍待核对，不能宣称完整范围已验收。

3. 重跑补齐流程，确认已齐全时不再写入：

   ```powershell
   node tools/asset-convert/src/development-recovery-cli.mjs --game-dir "D:/Program Files (x86)/Warcraft3" --out tools/asset-convert/tmp/development-manifest/manual-recovery.json
   $LASTEXITCODE
   ```

   将路径改为实际原版目录。本机预期 `status=sources_available`、`passes=0`、退出码 `0`。首次缺表时允许解包后成功；若仍缺失则应返回非零并保留原因，不得显示成功。

4. 运行边界回归：

   ```powershell
   node tools/asset-convert/src/development-manifest.test.mjs
   node tools/asset-convert/src/development-recovery.test.mjs
   ```

   预期分别 2 项和 4 项通过。测试在独立临时目录验证缺表、损坏表、JSON 优先级、注释排除、图标别名、覆盖候选保留、解包失败和轮数上限，不需要手动删除真实缓存。

本轮验收的是引用发现、来源追踪和补齐行为，不包含粒子／光晕画面、玩家端导入或地图视觉验收；这些仍按重构路线图单独实施。
