# demo_mod

最小内容包示例（D3）。将本目录绝对路径经 `ContentRegistry.register_package` 挂载后 `commit_snapshot`。

第一版支持**整文件覆盖**（同逻辑路径后注册优先），不实现字段级 JSON patch。

```powershell
# 挂载后新对局应走 overlay；commit_base_snapshot 卸载
```

`Units/UnitUI.json` 可放覆盖表；缺省时仅验证 manifest 与注册流程。
