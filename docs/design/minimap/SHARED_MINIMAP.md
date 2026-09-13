# 编辑器 / 游戏小地图共享实现

2026-09-13，取代 MINIMAP.md 中“游戏内尚未实现”的历史现状描述。

两端场景的 Overlay 节点现在均使用 scripts/map/minimap/minimap_view.gd。该 Control 绑定底图 TextureRect，统一纹理显示、按比例居中、UV/点击映射、点击拖动信号、相机多边形裁剪、图标/圆点/方块绘制。调用方在 draw 回调提供已筛选的标记，通过 bind_background / set_texture / draw_marker / draw_camera 使用，无需依赖编辑器窗口或游戏实体。

其他共用逻辑：minimap_background.gd 加载 PNG/TGA 预渲染图；minimap_marker_rules.gd 分类金矿、起始点、中立建筑、野怪；已有 MapMinimapRaster 负责实时底图和增量更新，MapMinimapUtils 负责世界坐标与相机投影。

编辑器适配层仍负责文档、撤销重做、树林遮罩、野怪距离聚合和显示开关；游戏适配层仍负责实时实体位置、WorldMembership、队伍色和 HUD 行为。显式 nbmm_icon=false 两端均尊重。中立建筑分类缓存以 typeId+owner 为键，重新 configure 时清空。

共享显示层不扫描世界、不访问地图文档，不判断任何玩家可见性。当前游戏旧实现只有 WorldMembership 筛选，尚无完整战争迷雾过滤；本次保留其既有行为，没有宣称补齐迷雾。将来游戏适配层必须在传入标记前完成可见性过滤。

验收：selftest_shared_minimap.tscn 在 D3D12 下检查两端使用相同脚本、三种控件比例的标记位置/UV往返、点击与拖动信号、留白拒绝、超界相机裁剪、中立建筑分类。selftest_editor_minimap.tscn 保持 LT 标记数量、实时回退、矩形地图点击等回归通过。
