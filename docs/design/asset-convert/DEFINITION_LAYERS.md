# 定义表覆盖规则与迁移验收

共享配置为 `packages/content/definitions/layer_policy.json`，当前默认 `base`，保留现有游戏逻辑使用基础表的行为。这里的配置仅选择 Func／Strings 定义层，**不等同于模型的 TFT／RoC 版本选择**。

## 规则

- `base`：基础层。
- `melee_roc`／`melee_tft`：基础层加 `Melee_V0/`／`Melee_V1/`。
- `custom_roc`／`custom_tft`：基础层加 `Custom_V0/`／`Custom_V1/`。
- 每次只选择一个族和版本，不把对战、自定义、RoC 和 TFT 全部叠加为游戏生效值。这是本项目明确采用的规则，不宣称还原所有原版地图加载语义。
- 同一逻辑文件内按对象 ID、字段合并；ID 区分大小写，字段键统一小写。后层出现的字段覆盖前层，未出现的字段继承，显式空字符串清空；同文件重复字段也遵循最后一次赋值。
- 整行 `//`／`;` 注释忽略。单值外层引号剥离；`"L1","L2"` 多等级字符串保留给 tooltip 处理。
- 扫描报告记录实际获胜字段的来源，覆盖历史保留在 `definition_conflicts`。`candidates` 是扫描专用审计模式，仍收集全部覆盖层；不是运行时配置。

本轮已接入：`CommandButtonCatalog`、`WorkerBuildListCatalog`、`UnitRequiresCatalog`、`ItemCatalog`。四者共用 `definition_layers.gd` 和纯计算合并器，命令卡原有解析职责移入合并器后入口降到 435 行。运行时仍经 `RuntimeAssets.resolve` 读取，保留 AssetProvider 的路径覆盖；扫描器当前只读取指定定义目录，尚不包含运行时 mod 覆盖。

尚未接入：`Wc3IdCatalog` 的地图／编辑器显示数据读取。该文件目前 935 行，后续须先按模型路径解析、面板显示等真实职责拆分，再迁移，不能继续向超限文件添加逻辑。动态脚本引用、SLK 数值表版本及模型 edition 对齐仍另行核对。因此 `coverage.complete` 保持 false，不能在此次提交后宣称所有入口已经统一。

配置在目录对象创建时读取，已有目录有自己的缓存；更改共享默认配置后应重启程序。CLI 的 `--definition-profile` 只覆盖本次扫描或补齐任务，不改变游戏配置。缺少所选层的文件时继承已有层，报告输入列表可核对实际参与的文件；目前尚未建立不同客户端版本必须具有哪些覆盖文件的完整校验。

## 手动验收

在仓库根目录执行，所有命令可直接粘贴到 PowerShell：

```powershell
node tools/asset-convert/src/development-manifest-cli.mjs
node tools/asset-convert/src/development-manifest-cli.mjs --definition-profile candidates --out tools/asset-convert/tmp/development-manifest/candidates.json
```

当前本机默认清单预期 339 个对象、275 个模型、519 个纹理，缺失和未解析均为 0，1 条重复字段差异。审计候选清单预期 347 个对象、276 个模型、527 个纹理，214 条差异；比上轮 211 多出的记录来自现在保留的文件内重复赋值。这两个结果用途不同，不能要求数量相同。

```powershell
node tools/asset-convert/src/definition-layers.test.mjs
node tools/asset-convert/src/development-manifest.test.mjs
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
node tools/asset-convert/src/definition-layers-integration.test.mjs
```

前两条分别应通过 2 项测试。最后一条需本机 Godot 开发工具，成功时打印 `Definition layer cross-language and four-catalog integration passed`；它在独立临时项目中验证基础／自定义两套配置下，建造列表与命令卡一致、空值清除需求、物品图标覆盖，以及 JS／Godot 的字段、来源和覆盖历史完全一致。文件 I/O 与未调用的 tooltip／图标处理依赖使用测试替身，不等于完整游戏启动验收。

游戏内人工回归：重新启动开发地图，选农民核对建造按钮及科技置灰条件，选兵营核对训练列表，再检查物品图标。默认基础配置下上述逻辑应与重构前一致。地图／编辑器面板当前仍走旧入口，不能用它来判定本轮配置切换是否生效。
