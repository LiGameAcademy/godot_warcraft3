# 编辑器地图文件 v1

扩展名：`.wc3map.json`。UTF-8 JSON，格式标识 `godot-wc3-map`，`version: 1`。
这是编辑器自己的文档格式，不是 w3m/w3x，也不是旧版只包含高度图的 JSON。

## 文件内容

| 字段 | 内容 |
| --- | --- |
| format / version | 必须匹配支持的格式与版本；未知版本明确拒绝，当前地图不变 |
| terrain | Wc3Heightfield 完整输出：尺寸、原点、材质目录、高度、水高、地表索引/变体、悬崖索引/变体/层高、标记 |
| units | Wc3UnitList 输出，保留原始 typeId、creationNumber、坐标、朝向、缩放、owner 及支持的属性 |
| doodads | Wc3DoodadList 输出，包括特殊装饰物及原始 id、creationNumber 等 |
| info | 地图信息字典 |
| pathing | 静态寻路网格及原点；没有网格时为 null。动态对象阻挡由表现/寻路层重建 |
| source | 来源名称与目录，供追溯；打开用户地图时不恢复为输出目录 |

未知根字段、地形字段、对象字段保留。对象额外字段以 creationNumber 关联，因此删除其他对象不会错配。删除对象时相应额外字段不写入；撤销恢复相同编号后可以重新带回。已支持字段以编辑结果为准。JSON 数字读回后类型变化，匹配编号时统一转为整数。

文件目前限制每边 3–513 个地形顶点，静态寻路网格每边最多 2048。加载前检查核心类型、尺寸、数组长度、有限数值、地表索引、对象实例编号及位置/朝向。此检查尚不等于原版所有字段的语义校验。

## 保存与加载保证

- 保存完整单文件，不再附带写回导入地图目录中的 units.json、doodads.json 或小地图。
- 同目录写临时文件，刷新并检查写入状态后改名提交。提交失败保留已有目标文件及文档脏标记，删除本次临时文件。
- 已有目标文件替换已在当前 Windows/Godot 环境测试；不承诺断电时文件系统级持久性。
- 解析与校验成功、候选对象构造完成后才替换当前编辑文档；失败保留当前文档和历史。
- 不支持的格式/版本及损坏文件返回明确原因。旧高度图单文件没有单位等完整数据，当前不提供自动迁移。
- 解析地图目录仍可从示例列表导入。地形、单位、装饰物、info 必须存在且有效；先校验所有文件，再统一替换文档，损坏或缺失核心数据保持当前文档不变。pathing.json 不存在时明确警告将合成寻路；存在但损坏则拒绝。警告随用户地图文件保留为 importWarnings。

## 界面操作

首次“文件 → 保存”选择路径；以后“保存”使用已选路径。“另存为”选择新路径。
“文件 → 打开”窗口中的“打开编辑器地图文件…”可选取本格式；原示例列表继续用于导入。
保存不自动导出小地图；小地图导出仍为独立菜单功能。未保存内容在新建、打开、菜单退出及主窗口关闭时要求明确放弃更改；可取消后先保存。

## 验证

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --headless --path . --log-file ./logs/editor-map-file-test.log --script res://tests/unit/selftest_editor_map_file.gd
```

已通过：地形全部数组、单位/建筑、树木、地图信息和静态寻路往返；已有文件覆盖；失败保存保留原文件和脏标记；未知字段随实例保留；损坏 JSON、未来版本、短数组、非法坐标、重复实例编号、损坏寻路数组拒绝且保留原文档；保存不写源对象文件；加载后实例编号分配继续递增。

测试夹具保存在 tmp/editor-map-file-*，便于查看。该自测验证存储层，不替代真实窗口交互、原版视觉与完整运行预览验收。

导入回归：`tests/unit/selftest_editor_map_import.gd` 验证六张现有地图均可导入；泰瑞纳斯看台缺失 pathing.json，明确提示这一限制。单位/装饰物数量分别为 Echo Isles 97/2491、Lost Temple 113/4896、Gnoll Wood 144/5596、Terenas Stand 91/1568、Turtle Rock 115/2377、Twisted Meadows 149/3494。隔离夹具验证四种核心文件损坏、单位文件缺失和寻路文件损坏均不替换脏文档。

## 文件菜单与预览链路

`tests/integration/selftest_editor_file_flow.tscn` 从单位笔刷放置开始，验证首次保存打开文件窗口、取消保存、另存为、继续编辑后保存到原路径、取消打开时保留未保存更改、新建后重新打开、旧历史清空、损坏文件打开失败保护，以及重开后进入并返回预览。测试通过实际菜单处理器、文件窗口信号和异步打开处理器执行，不模拟操作系统鼠标点击或文件列表导航。

该测试复现了文件选择信号触发时文件窗口仍持有模态焦点、与未保存确认窗口冲突的错误。选择文件处理器现在先隐藏文件窗口，再进行保存或打开确认。

RTX 2070 / D3D12 实际渲染运行 PASS（0 failures），完整地形高度与纹理数组按数值比较一致；单位原始 ID、文件关联、脏标记、历史及预览快照符合断言。仍有系统证书、旧窗口 API 弃用和退出时 ObjectDB 泄漏警告，需后续排查；此结果不代表完整人工界面验收或所有资源生命周期已通过。

```powershell
& 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe' --path . --log-file ./logs/editor-file-flow-rendered.log res://tests/integration/selftest_editor_file_flow.tscn
```

后续生命周期检查：文件流程测试现在等待预览节点真正退出场景并完成一帧释放，再连续重复三次打开/关闭预览。实际渲染测试通过，每轮节点和孤立节点数量均不超过首轮基线（本次 783 / 11），每个关闭的预览实例均已释放。这只证明该测试范围内节点数量不增长，不能证明全部内存或缓存无泄漏。

详细退出日志将残留定位为一个引用计数为 0 的 RefCounted，仍未定位来源。headless 未复现；实际渲染禁用无障碍服务的对照仍复现，单独打开/释放 FileDialog 的最小对照未复现，因此目前不能归因于无障碍服务或文件窗口本身。未改变项目的无障碍设置。证据分别为 `logs/editor-file-flow-lifecycle.log`、`logs/editor-file-flow-no-accessibility.log`、`logs/file-dialog-lifecycle-probe.log`。同时已将 Inspector 的旧 move_to_foreground 调用改为 grab_focus，对照运行中不再出现该弃用警告。
