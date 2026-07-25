class_name Wc3RampKinds
extends RefCounted

## 斜坡派生态常量（romp 格字节、拓扑形态、条带轴）。
## 权威地图态仍是 Heightfield.flags 的 FLAG_RAMP；本文件只约定派生结构取值。

## romp 字节（与地表格或 tilepoint 网格同形，由 Logic 写入）：
## 0 无；1 单脊主条（挖洞 + CliffTrans）；2 宽坡甲板；3 宽坡外侧侧脊。
const ROMP_NONE := 0
const ROMP_SINGLE := 1
const ROMP_WIDE := 2
const ROMP_SIDE := 3

## 条带轴（笔刷 / placement.axis）
const AXIS_V := "v"
const AXIS_H := "h"

## 条带几何来源（analyze）
const STRIP_FACE := "face" ## 直崖面
const STRIP_SLOPE := "slope" ## 沿已有坡延伸

## 拓扑形态（Logic Dispatcher → Placement；Present 不推断）
const TOPO_STRAIGHT := 0
const TOPO_OUTER := 1
const TOPO_INNER := 2
const TOPO_DIAGONAL := 3

## CliffTrans 单角合法字符（与 Catalog.VALID_CHARS 对齐）
const CORNER_CHARS := "ABCHLX"
