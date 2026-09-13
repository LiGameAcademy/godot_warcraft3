# 当前地图运行预览

入口：文件 → 测试地图。当前实现为运行中的视觉预览，不含战斗、AI、触发器或玩家控制。

预览复制当前文档的完整内存数据，不要求先保存，不读取固定 Echo Isles/Lost Temple。独立 Window 和 World3D 复用 MapLoader、地形、单位、装饰物、相机与原版资源加载逻辑。显示原版模型及其已有运行时表现，隐藏编辑网格、开始点和掉落提示。原文档与预览副本互不写入；预览期间暂停后台笔刷和输入路由，避免轮询全局输入导致误编辑。

右键拖动平移，Ctrl+右键旋转，滚轮缩放；Esc、“返回编辑器”或窗口关闭返回。加载期间关闭会先隐藏窗口，等待异步地形构建完成再释放，随后恢复笔刷。缺少模型时显示占位对象数量警告；资源 ID 和路径级诊断仍需完善。

## 已验证

`tests/integration/selftest_editor_preview.tscn` 是场景测试，必须按场景运行，以便正常加载 Autoload，不能使用 `--script`。

```powershell
$editorGodot = 'C:/Users/Administrator/Desktop/Godot_v4.6.3-stable_win64_console.exe'
& $editorGodot --headless --path . --log-file ./logs/editor-preview-test.log res://tests/integration/selftest_editor_preview.tscn
& $editorGodot --path . --log-file ./logs/editor-preview-render-test.log res://tests/integration/selftest_editor_preview.tscn -- --capture-preview
```

测试通过：取消新建保留脏文档；菜单创建预览；副本包含未保存编辑；隔离世界；农民 hpea、主城 htow、树 LTlt 实际存在且无占位模型；传给地形表现的数据一致；后台笔刷禁用；退出与提前关闭后文档/脏标记不变且输入恢复。

已在 NVIDIA GeForce RTX 2070、D3D12 Forward+、Godot 4.6.3 下实际渲染，截图 `tmp/editor-preview.png` 为 1100×720。检查确认地形、农民、建筑和树木可见、编辑网格隐藏。修复工具面板初始居中尝试访问 screen -1 的问题，位置统一由现有编辑器定位逻辑设置。系统证书读取错误仍需单独排查。

后续已修复 LTlt 呈雪树外观的问题：按原版物体 texID/texFile 应用替换纹理，真实渲染已确认夏树为绿色；详见 [对象验收](OBJECT_ACCEPTANCE.md)。这不是全部原版视觉验收。真实鼠标操作、打开/保存完整人工流程、大规模性能和模型缺失清单仍待验。
