# 对象表现与命令验收

2026-09-13：本轮验证存储/命令/模型表现，不替代全部鼠标交互验收。

## 原版物体替换纹理

夏季树显示积雪的根因是转换工具给 replaceable slot 31 烘焙了 LordaeronSnowTree 默认纹理，运行时未应用 DestructableData 的覆盖字段。原始导出表中 LTlt 指定 texID=31、LordaeronSummerTree；WTtw 使用同一模型但指定 LordaeronWinterTree。因此应按对象定义替换槽位，不能把共享模型直接全局改绿，也不能仅根据地图 tileset 猜纹理。

Wc3IdCatalog 现暴露 tex_id；DoodadTexture 根据 tex_id/tex_file 替换对应 `_repN` 材质。单实例、MultiMesh、从批量提升为单实例的对象、工具面板模型预览共用该逻辑。只复制被影响的材质/mesh，不写模型缓存。缺少替换纹理时保留已有表现并记录路径警告；当前支持 StandardMaterial3D，其他对应槽位材质明确警告。

已验证：夏/冬材质隔离、共享源材质未变、MultiMesh 及 material_override 两种路径、槽位 31 不误匹配 310。真实地图预览的 LTlt 已断言使用夏季纹理；RTX 2070 / D3D12 Forward+ 渲染截图确认树为绿色。未宣称所有物体或所有季节组合完成视觉验收。

## 对象命令历史

单位和装饰物各放置三个实例，修改中间实例的位置、旋转、缩放及属性，再删除另一个实例；执行十轮完整撤销/重做，逐阶段比较按 creationNumber 排序的全部对象数据。还验证撤销后新增操作清除旧 redo 分支。

测试通过，无重复实例编号、错对象或属性漂移。对象数组顺序不作为不变量，实例编号及内容才是权威。此次属性覆盖验证命令 API；界面是否对每项都提供编辑控件，仍须单独验收。

```powershell
$editorGodot = 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe'
& $editorGodot --headless --path . --script res://tests/unit/selftest_doodad_texture.gd
& $editorGodot --headless --path . --script res://tests/unit/selftest_editor_object_history.gd
& $editorGodot --headless --path . res://tests/integration/selftest_editor_preview.tscn
```

以上三项均 PASS、退出码 0。实际渲染可添加 `-- --capture-preview` 并移除 `--headless`，结果保存至 tmp/editor-preview.png。环境仍存在系统证书读取错误，与这些断言独立记录。

## 单位属性窗口数据保留

属性窗口原先每次确认都重写所有普通属性，使自定义警戒范围变为默认值、中立 ID 13/14 变为列表中的其他归属，并将未修改的角度精度和生命/魔法默认哨兵值规范化。现按打开窗口时的控件值判断实际编辑，只写入发生变化的字段；未修改确认不新增命令，取消不写文档。增加中立 ID 13/14 选项及可编辑自定义警戒范围。窗口最小高度提高到 460，避免确定/取消按钮被裁掉。

`tests/integration/selftest_unit_properties.tscn` 经由单位笔刷属性信号、编辑器处理器和真实控件按钮，验证原始值保留、取消、修改、单条历史、编辑器撤销/重做及文件往返。内存数据严格比较；JSON 往返比较全部字段，允许整数/浮点解析类型差异及数值 1e-9 相对精度。headless 和 RTX 2070 / D3D12 两种运行均 PASS（0 failures）。实际渲染截图 `tmp/unit-properties.png` 确认普通页布局及底部按钮可见。测试未模拟完整鼠标双击选中链路；技能与掉落物品页目前仍只读，其他对象属性窗口未由本测试覆盖。

```powershell
& $editorGodot --headless --path . --log-file ./logs/unit-properties-test.log res://tests/integration/selftest_unit_properties.tscn
& $editorGodot --path . --log-file ./logs/unit-properties-rendered.log res://tests/integration/selftest_unit_properties.tscn -- --capture-properties
```

日志仍含既有系统证书读取错误及 `move_to_foreground` 弃用警告，未宣称完全无日志问题。

## 对象笔刷操作链路与中断拖动

`tests/integration/selftest_unit_brush_flow.tscn` 使用面板选择信号激活农民笔刷，再以摄像机投影得到的屏幕坐标调用输入路由使用的笔刷入口，验证放置、拾取、移动、旋转快捷键、双击属性、删除及相应撤销重做。它复现并修复了单位拖离后返回起点却停在途中位置的问题：移动判定必须对比当前文档位置，不能对比笔划起点快照。

同时验证单位和 LTlt 树木拖动途中 Esc、Delete 的历史完整性。清除选择（包括工具禁用）前先结束当前移动，避免已经落地的变化丢失历史；Esc 结束移动并清除选择，移动仍可撤销。拖动途中删除产生移动、删除两条命令，依次撤销可还原原始位置与实例。松开鼠标不会重复入栈。

headless 与 D3D12 数据断言均 PASS（0 failures）；该测试调用屏幕坐标笔刷接口，不覆盖操作系统事件投递、面板遮挡及完整人工交互。最初两种渲染方式均发现树木移动时材质为空错误，D3D12 堆栈指向 MapDoodadLayer.remove_by_creation_number 的立即释放，来自 MapLoader.update_doodad_instance 的移除重建路径。后续修复及验证见下节。

```powershell
& $editorGodot --headless --path . --log-file ./logs/unit-brush-flow.log res://tests/integration/selftest_unit_brush_flow.tscn
& $editorGodot --path . --log-file ./logs/unit-brush-flow-rendered.log res://tests/integration/selftest_unit_brush_flow.tscn
```

## 保留装饰物实例更新与阻挡记录

同类型、同变体的装饰物现在保留模型实例更新变换，保留材质与动画状态；记录导入基础缩放，避免反复更新将地图缩放不断相乘。类型或变体变化时仍替换模型。删除节点先移出场景，再在帧结束释放，完整重建也先移出旧节点，避免本帧查找命中已等待删除的旧对象。

同时修复 MapLoader 更新装饰物时重复追加 pathing 条目的问题：按 creationNumber 替换该实例的全部旧记录，阻挡重建仅使用当前位置。原有追加路径会使树木移动后继续留下旧位置阻挡。

`selftest_doodad_update.tscn` 在实际 D3D12 下连续 20 次移动/旋转非均匀缩放的原版 LTlt，验证模型身份不变、位置朝向正确、缩放不累积、始终只有一条最新阻挡记录；另验证变体替换及删除后模型与阻挡均消失。PASS（0 failures）。对象笔刷完整回归重跑也 PASS；两份实际渲染日志均不再含材质为空错误，仍保留系统证书错误，笔刷测试另有旧窗口 API 弃用警告。当前证据覆盖原版单实例树木，未将批量实例提升及所有模型种类视为全部通过。

```powershell
& $editorGodot --path . --log-file ./logs/doodad-update-rendered.log res://tests/integration/selftest_doodad_update.tscn
```

## 批量对象的地形高度同步

原先高度刷新只遍历独立对象节点，MultiMesh 根没有 doodad_data，导致批量对象继续留在旧高度；后续提升成单实例也使用旧条目。现按批量 creationNumber 索引更新每个可见实例的变换、缓存条目和变换缓存。已提升的实例保留隐藏槽位，由独立节点路径更新；已删除的实例不在索引内，刷新不会使其复活。

`selftest_doodad_batch_height.tscn` 使用原版 LTlt 模型显式建立八实例批次，验证全部实例跟随两次高度变化、提升后保持新高度、删除/提升槽位持续隐藏，以及高度恢复后对象回到地面。RTX 2070 / D3D12 测试 PASS（0 failures），日志仅剩系统证书错误。此测试专门覆盖批量分支，不宣称 LTlt 在正常导入的动画标记下必然选择批量模式。它需要真实渲染器，headless dummy 的 MultiMesh 变换读回不适用于该验证，测试会明确拒绝 headless。

```powershell
& $editorGodot --path . --log-file ./logs/doodad-batch-height-rendered.log res://tests/integration/selftest_doodad_batch_height.tscn
```

## 缺失模型引用报告

“查看 → 地图资源检查”使用当前文档和原版目录的实际路径解析器生成只读报告。按对象种类、ID、变体聚合，显示原因、原版 file 路径、实例数量及最多五个实例编号；合法模型不报警，use_click_helper 对象允许没有模型。报告可滚动、选择和复制，不修改地图或原版资源。

`selftest_asset_diagnostics.tscn` 使用真实 hpea 及内存中构造的未知 ID/缺失模型路径，验证分组计数、样例编号上限、路径保留、原版已存在资源通过、菜单 index_pressed 到报告窗口的连接及文档不变。D3D12 运行 PASS（0 failures）；截图 `tmp/asset-diagnostics.png` 已检查可读性及按钮布局。此检查只证明目录 ID 和转换模型路径可解析，不能发现已存在但损坏的模型、模型内部缺图、动画问题或全部视觉差异。

```powershell
& $editorGodot --path . --log-file ./logs/asset-diagnostics.log res://tests/integration/selftest_asset_diagnostics.tscn -- --capture
```

## 树木与装饰物属性窗口

装饰物笔刷接入输入路由已有的双击接口，打开确认窗口编辑朝向、X/Y/Z 缩放和生命百分比。未修改确认不写入、不增加历史；取消保留文档；真正修改记录单条 DoodadEditCommand，并更新现有模型和阻挡。WC3 Z 缩放对应 Godot Y，重复修改复用已记录的模型基础缩放。生命值存储为地图属性，视觉预览暂不模拟死亡状态，窗口明确显示该限制。

`selftest_doodad_properties.tscn` 经由面板信号放置原版 LTlt、屏幕坐标双击、确认/取消信号验证属性修改、完整撤销重做、保存重开以及模型身份和垂直缩放。实际 D3D12 测试 PASS（0 failures）；截图 `tmp/doodad-properties.png` 确认字段与底部按钮完整可见。本轮未新增变体或物品掉落编辑，未宣称模拟操作系统鼠标事件。

```powershell
& $editorGodot --path . --log-file ./logs/doodad-properties.log res://tests/integration/selftest_doodad_properties.tscn -- --capture
```

## 文本输入与相机焦点隔离

相机原先每帧读取全局 WASD/方向键状态，未判断属性浮窗或文本框焦点，输入文字时可能推动背景相机。键盘移动现要求主编辑窗口拥有焦点，且当前焦点不在 LineEdit/TextEdit 中；Ctrl/Alt/Meta 组合操作也不触发键盘平移。鼠标松开补偿仍先处理，避免失焦造成笔划无法结束。

`selftest_editor_input_focus.tscn` 在实际原生窗口中用 Input.parse_input_event 注入并刷新 W 键事件，确认主窗口可移动、组合键不平移、主窗口文本框和模态浮窗不推动相机、返回主窗口后恢复。断言文本框/模态检查时全局 W 确实处于按下状态，避免因丢焦清键而误通过。D3D12 测试 PASS（0 failures）。该测试验证原生窗口焦点和引擎输入状态，不宣称人工物理键盘操作已验收。

```powershell
& $editorGodot --path . --log-file ./logs/editor-input-focus.log res://tests/integration/selftest_editor_input_focus.tscn
```

## 引擎输入事件与撤销后的选择

`selftest_editor_input_events.tscn` 通过 Input.parse_input_event/flush_buffered_events 投递鼠标按下、拖动、释放及键盘事件，经过 GUI 和 unhandled_input 路由验证放置、Esc 取消预览、拖动、R 旋转、Delete、Ctrl+Z/Y。与直接调用笔刷方法的旧测试相比，该测试覆盖输入分发，但仍不等同操作系统物理输入；测试主动收起工具浮窗以检查主视口。

它发现撤销旋转后无条件清除选择，导致紧接着 Delete 无效果。现按实例编号保留仍存在的选择，移除已不存在的选择，单位和装饰物共用此规则。撤销/重做前先结束当前笔划，鼠标仍按住时也能撤销当前拖动，之后松开不新增过期命令。恢复已删除对象不会自动推断新的选择。

D3D12 输入事件测试 PASS（0 failures）；旧单位/树木操作链路回归也 PASS。输入事件测试日志仍有系统证书与退出 ObjectDB 警告；headless 旧回归退出时偶有 dummy 材质为空信息，未将这些日志问题视为已解决。

```powershell
& $editorGodot --path . --log-file ./logs/editor-input-events.log res://tests/integration/selftest_editor_input_events.tscn
```
