# 独立动效模式验收基线

2026-10-11，在产品实现 `48254374b3ac7031bc798d6aaf82e36d35a68f56`、协调者报告 `d33e6a6` 上先编写本轮需求和测试，尚未派遣开发修改实现。

`node --test acceptance/motion-mode.test.mjs`，Node v24.19.0：22 条，10 通过、12 失败，退出码 1。失败覆盖三态 manifest 尚不存在、always 仍读系统策略、off/无效字符串尚未保守处理，以及 renderer 没有收到明确模式。完整红灯输出临时保存在 `/tmp/likeit-motion-mode-red.txt`。

测试草稿在冻结前修正了夹具的默认参数，避免明确的 undefined 策略被 JavaScript 默认值替换为 false；以上是修正后的红灯结果。实现未改、没有根据实现缩减需求。冻结后测试由协调者负责，开发者禁止修改。

原 `docs/acceptance.sha256` 的 7 项与 `docs/confetti-acceptance.sha256` 的 5 项均匹配。原 46 条用例保持原样，本轮新增文件单独冻结。用户明确要求三种模式，新的 always 行为是需求变更，并非把既有失败伪装为通过。
