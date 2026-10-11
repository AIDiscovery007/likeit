# 原生身份与执行边界

## 已批准的身份语义

协调者于 2026-10-11 批准以本次命令内的播放条目一致性键进入实现，冻结契约不变。键是以下实际媒体字段的无歧义 JSON 数组序列化：

```text
[bundleIdentifier, processIdentifier, contentItemIdentifier, title, artist, album, duration]
```

来源必须为 `com.netease.163music`，PID 必须与当前已运行网易云一致；四个字符串字段必须非空，时长必须为有限正数。缺失、类型异常、来源不符均拒绝。PID 将比较限定在进程生命周期内，元数据额外区分条目；不跨命令缓存，不称为网易云库歌曲 ID、永久 ID 或跨重播稳定 ID。

批准依据是协调者核对的用户歌曲链接（网易云 song ID `1377163127`）与客户端系统媒体信息相符，并在同一 PID 下观测到《恋人》与 Antisocial 的条目 UUID 不同；当前歌曲的夹取读数一致，系统播放状态分别与 Play/Pause 菜单相符。窗口 AX 未暴露原生歌曲 ID，停止继续寻找该路径。完整证据与其局限见 `identity-research.md`。

## 读写约束

每个真实 snapshot 执行媒体 A → 菜单 → 媒体 B；A/B 键和播放状态必须相同，系统播放状态必须与唯一启用的 Pause/Play 菜单一致，喜欢状态必须来自唯一启用的 Like/Dislike 菜单。动作边界再次执行同样检查，只允许按下 Like，已喜欢不操作；点击之后仍需同曲、已喜欢的回读才能确认客户端成功。通信失败不重试点击。

这种夹取降低可观测竞态，不让菜单动作原子绑定歌曲。最后一次读取与 AX 动作之间仍可能换歌；该窄竞态必须保留在产品限制中。云端同步不由菜单状态证明。

## 依赖和构建

MediaRemote adapter 固定来源为 `ungive/mediaremote-adapter` 的 `797729d9b16316dc313844476c153d7a107ca0df`。`vendor/mediaremote-adapter/SOURCE.json` 记录所保留上游文件的摘要；源码保持原样，只保留 framework 构建需要的代码、入口、许可和原始 CMake 配置，不携带 TestClient 实现或 CLI。上游库内 `adapter/test.m` 的编译依赖 `src/test/NowPlayingTest.h`，仅原样保留此声明头文件，不构建或运行 TestClient。

开发者执行 `python3 scripts/build-native.py`，用已有 Apple Command Line Tools 编译两架构、合并并 ad-hoc 签名。脚本不下载或安装工具，先核对源文件摘要，构建阶段不执行任何媒体命令。库中包含上游未调用的控制及测试函数，但运行时只允许调用 Perl 入口的 `get --no-artwork`。二进制、入口和 BSD 许可随 `assets/native` 提供；终端用户不编译或下载 helper。

`assets/native/BUILD.json` 记录编译器、完整命令和产物 SHA-256。构建及 lipo 验证两个架构不代表 Intel 真机验证；ad-hoc 签名不代表 Developer ID 签名或公证。实际 Raycast 分发、权限与客户端行为仍由协调者单独验收。

## 控制器与协议

协调者另行批准随包提供 `native/LikeitController.swift` 构建的通用二进制。它只依赖系统 AppKit / ApplicationServices，通过不弹窗的 `AXIsProcessTrusted` 检查辅助功能权限。正式路径不再使用 System Events 或自动化授权；原始 JXA 脚本仅供诊断。

Node 每次命令启动一个控制器，唯一参数为 Raycast supportPath 内固定 `netease.lock` 的绝对路径；媒体依赖从控制器所在目录取得。原生通过 `O_CLOEXEC | O_NOFOLLOW` 打开锁文件、`flock(LOCK_EX | LOCK_NB)` 竞争锁，成功返回 `{"ready":true}`，冲突返回 `{"busy":true}` 并退出。锁文件不删除，文件描述符在整个会话中保持打开，包括动作与确认阶段，且不会跨 exec 传给 Perl。退出自动释放锁。

协议为一行一个 JSON，只有 `{"command":"read"}` 和 `{"command":"press","trackKey":"…"}`。回复分别包含 `snapshot` 或 `action`；任何异常回复 `error`，不由原生决定完整业务结果。正式入口用这两个方法调用已验收的 `likeCurrentTrack(port)`。控制器每次会话最多发出一个 AXPress，动作返回后仍由 TypeScript 流程读取确认。

每个媒体子进程四秒期限、stdout+stderr 总计 64 KiB 上限；请求九秒、启动两秒，Node 会话总计 25 秒。超时杀整个进程组；普通完成关闭 stdin，500ms 未结束则强制终止，再最多等一秒。Node 退出、SIGINT、SIGTERM 都结束进程组。控制器另有 30 秒硬期限及父进程消失检查，以应对 Node 无法处理的异常退出；它会终止正在读取的 Perl 子进程并释放锁。动作或确认期间异常仍反馈结果未确认，不重复点击。

开发阶段只执行过一次真实 `read`：得到网易云 PID 5511、Antisocial、playing=true、liked=false，夹取键一致。此时系统艺术家字段为 Ed Sheeran/Travis Scott，条目 UUID 与早期样本不同；这是不跨命令缓存的又一理由。未执行 `press`，真实收藏、并发和异常退出行为仍待协调者验收。
