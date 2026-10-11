# Likeit

面向 macOS 网易云音乐的 Raycast `like` 命令，目标是收藏当前正在播放的歌曲，重复执行不取消喜欢。

**当前为开发预览，尚不能执行收藏。** 后台菜单读取已确认可用，但可靠的歌曲身份与播放状态来源仍未确定。当前入口只做只读检查并显示 HUD，不会点击喜欢、启动网易云或改变播放。核心收藏流程已实现，尚未连接真实写入 adapter；不代表真实环境验收通过。

## 在 Raycast 中运行

开发环境需要 Node.js、npm 和 Raycast。安装项目依赖后运行：

```sh
npm install
npm run dev
```

在 Raycast 搜索 `like`，选择 **Like Current Track**。搜索关键词不会自动创建别名；可在 Raycast 设置中为该命令手动设置 `like` alias 或全局快捷键。

当前命令仅支持 macOS，读取已经运行的 `com.netease.163music`。网易云未运行会直接提示；身份或播放状态不可确认时提示未执行收藏。读取超过 4 秒会终止读取进程并提示失败或超时。

## 权限与诊断

读取通过 macOS 自带的 `/usr/bin/osascript` 与 System Events 完成。实际从 Raycast 执行时可能需要在“系统设置 → 隐私与安全性”允许 Raycast 的辅助功能权限，以及“自动化 → System Events”。权限由用户决定；本项目不修改系统权限。当前开发终端可读不代表 Raycast 已获授权。

只读诊断命令：

```sh
/usr/bin/osascript -l JavaScript assets/netease-state.jxa
```

输出包含运行状态、菜单证据与当前窗口名称。没有可靠身份时 `trackKey` 为 `null`；尚未验证播放信号时 `state` 为 `unknown`。`liked` 来自唯一启用的 `Like` / `Dislike` 或中文对应菜单，仅为客户端菜单观测，不是歌曲绑定或云端同步证明。分享诊断输出前可删去窗口名称。

## 当前证据与限制

- 本机网易云 3.1.13 在后台、无可读取窗口时，System Events 能读取启用的 `Play` 和 `Dislike`；只读过程没有激活网易云。
- 当前 AX 进程和菜单未提供可用歌曲 ID。不会用曲名、菜单标题、队列序号或常量代替可靠身份。
- 没有引入 MediaRemote、外部 helper 或运行时编译。身份依赖方案仍需评审。
- 原生收藏、动态播放状态、中英文切换、权限失败、Raycast 端到端、全屏/最小化、账号与网络场景均未验证。
- 当前没有写入路径；跨进程写入互斥尚未实现。写入 adapter 获准后，必须先实现互斥再接入命令。
- 将来即使点击前后核对同一歌曲，也无法使网易云的菜单动作原子绑定某个歌曲 ID。收藏后的客户端确认不代表云端同步成功。

## 开发验证

```sh
npm run build
npm run lint
```

开发者不编写、修改或运行测试。行为验收与真实音乐状态变更由协调会话负责；固定验收资料见 `docs/handoff.md` 与 `docs/development-plan.md`。
