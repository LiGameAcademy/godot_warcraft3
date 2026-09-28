# 开发地图资产引用清单

此清单用于确定新管线迁移范围，当前是可追溯的静态候选清单，不是已验收的游戏发布清单。

## 生成

```powershell
node tools/asset-convert/src/development-manifest-cli.mjs
node tools/asset-convert/src/development-manifest-cli.mjs --worker-result <success-result.json绝对路径>
node tools/asset-convert/src/development-manifest.test.mjs
```

默认读取 `assets/map-parsed/echoisles`、`assets/slk-exported` 和 `.cache/wc3-assets`，以 `hpea,htow` 作为人族开局补充种子。种子依据 `MeleeRacePreview` 的人族配置；更改种族／开局配置时需显式传入 `--seeds`。支持 `--map`、`--definitions`、`--source`、`--out`。`--worker-result` 可重复，但同一资产有多份匹配证据时标记歧义，不擅自挑选成功记录。

输出默认位于忽略目录 `tools/asset-convert/tmp/development-manifest/echoisles.json`。较小的 `assets/.staging/wc3-assets` 可用于测试，但不能据此判断完整解包库缺失。

## 当前覆盖

- 地图单位、装饰物及其放置变体；开始点 `sloc` 作为地图标记处理。
- 人族开局种子及基础定义表中的建造、训练、升级、出售、技能、Buff／Effect 引用。
- 已知对象 ID 的技能 Data 字段引用，保守纳入候选，包括可能召唤的单位。
- 定义表明确写出的模型和纹理路径；MDL 引用可解析到磁盘上的 MDX，忽略路径大小写。
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
