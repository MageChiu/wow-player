# mock WoW 目录夹具（A1/A9 测试用）

用于测试平台适配层的目录识别。结构模拟 WoW 根目录：

```text
wow_retail_mock/
  _retail_/
    Interface/AddOns/.keep
    WTF/.keep
  _classic_/
    Interface/AddOns/.keep
    WTF/.keep
```

集成测试 `tests/platform_fixture.rs` 会读取此目录并断言可识别出
Retail 与 Classic 两个安装。
