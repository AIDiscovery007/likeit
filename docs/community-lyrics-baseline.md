# C0 验收基线

2026-10-11，协调者在独立worktree从0eea051提交本契约。开发产品代码尚未开始。

执行 `node --test acceptance/community-lyrics.test.mjs`：2个顶层测试均红灯，原因分别为community provider未实现与desktopLyricsSource偏好不存在；0 skipped，0 todo。该结果是预期基线，不是验收通过。

冻结合成Swift driver预期51个行为结果；覆盖解析、主词/翻译/空格、恶意与无效XML、时间边界、可信ID路线与拒绝歧义、双源fallback、严格元数据、纯文本/纯音乐、HTTP/大小、取消/迟到、缓存上限、失败重试、15秒总时限与429冷却。另一个顶层测试检查真实Raycast偏好与桌面入口。测试不请求公网、不启动音乐app，不保存商业歌词正文。

`community-lyrics.sha256`覆盖本次research、plan、feature、handoff、baseline、driver和Node测试。所有旧sha256清单与所列文件也是冻结文件。开发者不修改也不运行测试；协调者不通过改断言为失败实现开绿灯。

额外review范围：取消请求实际释放、主线程不解析大文件、URL固定、无凭据、生命周期UI清理、同一app再次打开换源、包内资源和manifest一致、旧收藏/官方歌词/音频回归。人工实机验收单独记录，build和离线测试不可代替。
