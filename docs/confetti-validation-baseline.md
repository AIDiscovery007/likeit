# 彩带迭代验收基线

2026-10-11，由协调者在实现起点 `19f39386390620d49b20b7aa42df1bac325ed2ab` 上添加本轮验收。

新增 `acceptance/confetti-feedback.test.mjs` 定义 18 个行为用例。首次执行 `node --test acceptance/confetti-feedback.test.mjs`，Node v24.19.0，退出码 1，原因是 `src/result-feedback.ts` 尚不存在（ERR_MODULE_NOT_FOUND）。这是预期红灯；用例尚未执行，不能计作通过。

旧 28 条测试和 `docs/acceptance.sha256` 不修改。本轮独立清单 `docs/confetti-acceptance.sha256` 冻结新计划、研究、BDD、测试与本记录；具体基线 commit SHA 在派遣消息中给出。开发者只实现，测试由协调者运行。新旧测试失败都修实现，不通过改断言变绿。

既有 Raycast 内置彩带的单次预览仅证明双侧视觉；外部 URL 有确认框。正式扩展内调用、减少动态效果、焦点/Space、并发及收藏联动仍待本轮验证，不提前算通过。
