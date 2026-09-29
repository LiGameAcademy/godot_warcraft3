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

已接入：`CommandButtonCatalog`、`WorkerBuildListCatalog`、`UnitRequiresCatalog`、`ItemCatalog`、`Wc3IdCatalog`。五者共用 `definition_layers.gd` 和纯计算合并器。运行时仍经 `RuntimeAssets.resolve` 读取，保留 AssetProvider 的路径覆盖；扫描器当前只读取指定定义目录，尚不包含运行时 mod 覆盖。

`Wc3IdCatalog` 已由 935 行拆为公开入口（156 行）、数据加载（284 行）、模型路径解析（190 行）、面板筛选（288 行）。公开方法保持不变，子模块只接收显式数据／定义存储对象。地图显示名、图标及按钮位置现在跟随共享 profile；不再混读全部覆盖层。空名称／图标按规则清空，空按钮位置归零，因此此前由未启用覆盖层提供的名称、图标或位置可能变化。

动态脚本引用、运行时 mod 来源、SLK 数值表版本及模型 edition 对齐仍需核对。因此 `coverage.complete` 保持 false；已统一这五个 Func／Strings 入口不代表开发地图全部依赖已经覆盖。

配置在目录对象创建时读取，已有目录有自己的缓存；更改共享默认配置后应重启程序。CLI 的 `--definition-profile` 只覆盖本次扫描或补齐任务，不改变游戏配置。缺少所选层的文件时继承已有层，报告输入列表可核对实际参与的文件；目前尚未建立不同客户端版本必须具有哪些覆盖文件的完整校验。

## 手动验收

在仓库根目录执行，所有命令可直接粘贴到 PowerShell：

```powershell
node tools/asset-convert/src/development-manifest-cli.mjs
node tools/asset-convert/src/development-manifest-cli.mjs --definition-profile candidates --out tools/asset-convert/tmp/development-manifest/candidates.json
```

纳入脚本字面量后，当前本机默认清单预期 339 个对象、281 个模型、522 个纹理，缺失和未解析均为 0，1 条重复字段差异。审计候选清单预期 347 个对象、282 个模型、530 个纹理，214 条差异；比最初 211 多出的记录来自现在保留的文件内重复赋值。这两个结果用途不同，不能要求数量相同。

```powershell
node tools/asset-convert/src/definition-layers.test.mjs
node tools/asset-convert/src/development-manifest.test.mjs
$env:GODOT = 'D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
node tools/asset-convert/src/definition-layers-integration.test.mjs
```

前两条分别应通过 2 项测试。最后一条需本机 Godot 开发工具，成功时打印 `Definition layer cross-language and five-catalog integration passed`；它在独立临时项目中验证基础／自定义两套配置下，五个目录的一致性，以及 JS／Godot 的字段、来源和覆盖历史完全一致。新增 25 项地图目录断言，每个 profile 都执行：显示名清空、图标一致、按钮位置、SLK 合并、注入条目、未知 ID、TFT／RoC 路径、肖像、变体、筛选、开始点排序、尺寸及实例隔离。文件 I/O、定义存储和未调用的 tooltip／图片加载使用测试替身；模型文件仅用于路径查询，不代表真实模型渲染验证。

游戏内人工回归：重新启动开发地图，选农民核对建造按钮及科技置灰条件，选兵营核对训练列表，再检查物品图标。默认基础配置下上述逻辑应与重构前一致。

地图／编辑器人工验收：

1. 重启编辑器项目，打开开发地图；切换人族和中立面板，确认单位／英雄／建筑分类正常，开始点仍置于建筑分类首位。
2. 检查农民等相同单位的图标与游戏命令卡一致；名称应来自当前 profile 的 UnitStrings，不再被其他 profile 覆盖。
3. 在中立面板切换等级与地形集，再切换装饰物分类，确认过滤正常。
4. 预览牧师等具有版本模型的单位并查看肖像，再预览有多个变体的装饰物。外形、肖像匹配和变体选择不应因拆分发生变化；模型 edition 与定义 profile 是两套独立配置。
5. 查看输出面板，确认没有新出现的脚本解析或资源引用错误。若发现名称／图标变化，先对照共享 profile 的来源字段，区分规则修正与回归。
