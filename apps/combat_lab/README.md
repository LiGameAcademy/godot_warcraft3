# 固定站位战斗实验

独立 Godot 4.7.2 Mono 工程，复用纯 C# StationaryCombat；不接管主游戏的战斗权威，不包含移动或追击。圆形单位、血条与挥击效果由 Godot 绘制，不需要 Warcraft III 素材。

## 启动

从仓库根执行（Godot 路径换成自己的 Mono 版本）：

~~~powershell
./tools/workspace/Start-CombatLab.ps1 -Godot "D:/GameMaker/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe"
~~~

需要 .NET SDK；目标框架仍为 net8.0。启动脚本仅为当前子进程设置 LatestMajor，以支持仅安装 .NET 10 的本机，不更改系统配置。也可构建 CombatLab.csproj 后用 Mono 编辑器打开本目录 project.godot。

## 操作与黑盒验收

- 左键选中任一方存活单位，右键敌人攻击；蓝方1可攻击红方3/4，红方5在射程外。射程外或同阵营命令拒绝并保留旧任务。
- Space / 停止：取消待出手攻击；之后换目标或重新攻击，不能重置已有冷却。
- D / 双方交战：显式向双方下令；没有自动索敌。
- 1 / 基础：检查前摇、扣血和换目标；2 / 互杀：按D，双方同帧死亡，尸体不能选择；3 / 多组：24单位配对交战。
- P 暂停/继续；N 暂停并前进一帧；R 重置当前场景。
- F5 保存；F9 恢复并暂停。前摇、冷却、血量、目标、随机状态和未执行命令均恢复；按P继续。历史命中与死亡效果不重播。
- 表现速度滑块只改变挥击/闪光效果，设为0也不改变逻辑扣血。

存档位于此独立应用的 user://save.json，与主游戏及移动实验隔离。自检使用 user://selftest/save.json。资源配置只读；生命、订单、冷却仅由内核持有。存档为本实验完整根快照，不宣称是主游戏完整存档。

## 自动检查

~~~powershell
./tests/combat_lab/Test-CombatLab.ps1 -Godot "<Godot Mono console.exe>" -Profiles
~~~

包含纯逻辑、视口鼠标路由、按钮、存读档和表现独立检查。可选 Profiles 为24/300/500各启动独立 CLI/Godot 冷进程，600逻辑帧逐帧对照直接内核的哈希与事件，保留全部首帧并按30Hz判断。测量仅覆盖宿主逻辑 Step，不包含绘制、存读档IO及整个渲染帧。

本分支叠加宿主 PR #47；内核固定 c1ce455（战斗 PR #151–153）。不改变移动实现。用户黑盒、原 M3 性能门和主游戏战斗迁移需分别验收；新样本通过不能覆盖此前 #149 500单位冷启动33.8457ms失败记录。
