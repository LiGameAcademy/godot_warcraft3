# 对局交互

- InteractionModule：唯一瞄准状态与光标/选择器互斥。
- CommandInputModule：移动、攻击、采集等命令下发。
- MatchInputController：显式 handle_input / handle_unhandled 入口，保持背包 GUI、瞄准确认、选择器、热键的原有处理顺序。该子节点不自行注册 _input，避免重复消费。鼠标位置也由它持有。
- WorldPicker：地形射线拾取，使用当前导航高度数据。
- InteractionFeedback：移动确认、集结旗与 GUI 阻挡查询。

模块不依赖 GameDirector 类型。建造提交/取消暂通过明确回调接入；调试功能通过既有 DebugToolsModule 和路径开关信号衔接。

测试：selftest_match_input、selftest_interaction_module、selftest_command_input_module、selftest_command_card_module，以及真实地图建造/重开回归。
