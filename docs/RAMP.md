# 斜坡（Ramp）重建说明

> **分支：`feature/ramp-rebuild`**  
> **状态：旧实现已清空，等待逐步重做。**  
> 直崖见 [CLIFF.md](CLIFF.md)。

---

## 当前基线（2026-07）

已移除 / 旁路：

| 层 | 行为 |
|----|------|
| 笔刷 | `paint_ramp_at` / `try_paint_ramp_at` 拒绝并提示 |
| romp / CliffTrans | `collect_ramp_placements` 恒空；builder 不放 CliffTrans |
| 地面 | 仅直崖 `should_leave_gap`；无甲板 / 无坡面插值 |
| 调试 | `MapRampDebugLayer` 空实现；默认关闭 |
| 水体 | 忽略 `FLAG_RAMP`（岸浪不走斜坡分支） |

仍保留（只读 / 兼容）：

- `Wc3Coords.FLAG_RAMP` 与 `is_ramp_flag` / `is_ramp_tile`（读旧图旗位）
- 空壳 API：`romp_kind_at`、`sample_ramp_plane_height`、`apply_ramp_entrance_heights` 等

旧 WIP（切分支前）在 stash：`wip-ramp-before-rebuild`。

---

## 重建约定

1. **一次只做一步**，由用户指定；每步可独立验收。
2. 对照 WE / HiveWE：蓝菱形 = `FLAG_RAMP`；侧脊 `CliffTrans`；宽坡内部甲板。
3. 不恢复「边修边补」的旧耦合；新逻辑按文档逐步接入。

---

## 验收清单（重建完成后勾）

- [ ] 单脊：挖洞 + 双侧 CliffTrans
- [ ] 宽坡：邻列菱形 → 内部甲板 + 外侧 CliffTrans
- [ ] U 凹：隔列独立，中间空列不填
- [ ] 背后天窗：高台后缘 Cliffs/CliffTrans
- [ ] 脚底无棋盘缝，侧脊不被泥地三角面替换
