# O1 review 补充：无效 PKCS8 封装

这是对原 O1 “无效PEM应throw”要求的新增回归，不修改原冻结用例。

Given 一个合法测试 RSA PKCS8 私钥追加畸形 `[0] attributes`（A0 01 FF），且外层长度正确；When 请求签名；Then 必须拒绝。不得剥掉坏封装后仍签名。实现可明确只支持无 attributes 的 PKCS8 profile，或正确校验属性结构；本轮选择前者以保持范围简洁。

协调者在 `6a2eb0e` 上用相同输入实测：Node crypto.createPrivateKey 拒绝，而产品 Swift signer 接受。原 O1 17 项行为检查（18 个 Node tests）全部通过，并没有覆盖这个新发现。独立 Spec review 找到1个问题，Standards review 无发现。

协调者新增 acceptance/openapi-key-envelope.test.mjs，开发者只修产品，不改测试或原O1契约。真实账号、网络与用户配置均不涉及。
