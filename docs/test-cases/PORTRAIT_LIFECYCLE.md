# 头像加载与卸载回归

## 问题与处理

已选中英雄后立即卸载游戏，延迟头像任务仍可能创建或设置模型。头像组件现在在挂载和后续设置前检查自身及祖先是否已请求删除，离树时作废任务世代。

单独加载大法师头像也复现空材质引擎错误：TeamGlowBillboard的PrimitiveMesh基础材质为空，仅有表面覆盖。组件在设置阶段将该材质转入实例独有的PrimitiveMesh并去掉覆盖，保持有效材质，不修改缓存网格。此修复限定该结构，不对所有材质盲目替换。

## 验证

运行 `res://tests/unit/selftest_portrait_shutdown.tscn`：六项断言覆盖真实头像加载、正常显示、有效光晕材质、网格实例隔离、父场景queue_free取消任务、离树取消任务。需要本地已转换的大法师头像资产。

2026-09-13：`tmp/portrait-milestone-portrait.log` 六项PASS且无ERROR/WARNING。`tmp/portrait-shutdown-scene.log` 保存修复前四项功能PASS但仍有空材质错误的反例；不能只看脚本退出码或PASS文字。

真实英雄升级集成保持原本整场queue_free，不使用诊断模式的提前释放HUD方式。相关结果另见验收进展。无窗口检查可验证生命周期与材质引用，不能替代最终画面视觉验收。
