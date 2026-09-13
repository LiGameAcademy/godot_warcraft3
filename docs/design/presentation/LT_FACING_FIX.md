# LT 朝向核对与修复

2026-09-13。来源：当前 assets/map-parsed/losttemple（113 个单位、4,896 个装饰物）；本地 HiveWE b70f9b8 的 src/base/doodad.ixx 和 units.ixx；tools/asset-convert/src/mat4.js。

模型顶点、动画四元数与地图位置均使用 C(x,y,z)=(x,z,-y)。这是 determinant +1 的换轴旋转；绕 WC3 Z 的角 a 换到 Godot 后仍为绕 Y 的 a。HiveWE 对单位和装饰物均使用原始角度，不按类别镜像。

旧 yaw_wc3_to_godot 返回 PI-a，造成东西朝向颠倒，南北朝向恰好相同。当前 LT 有 452 个装饰物的角度受影响，其他对象多为南北方向，或模型外观对称不易察觉。改为返回 a，单位 API 作为兼容别名调用同一函数。独立实例、MultiMesh、批次提升、属性编辑及笔刷预览的调用均由此统一。未改地图文件、模型资产和已正确的单位移动逻辑。

验证：selftest_lt_facing 对所有装饰物变换，23 类实际单实例，以及 113 个实际单位根变换、模型根方向、动画启动后朝向做检查。期望来自独立的“先在 WC3 旋转源点，再换轴”计算，并覆盖任意角度、非均匀缩放。10,540 项检查通过。该验证不等于每个骨骼动画帧的视觉方向已复核，当前未复现单位单独朝向错误。

selftest_doodad_update、selftest_doodad_properties 验证连续更新、撤销重做、保存重开；selftest_doodad_batch_height 使用 D3D12 实际批次变换读回，覆盖不同角度、地形更新及提升独立实例后的朝向。

运行日志仍有环境证书读取错误；dummy renderer 属性测试退出时另有空材质警告，不能将测试通过描述为日志完全无错误。
