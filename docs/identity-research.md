# 歌曲身份只读评估

本页保留各阶段的观察与决策时间顺序。后续协调者已批准“本次命令内播放条目一致性键”和固定依赖打包，具体规则见 `native-design.md`；下文早期的 `trackKey=null` 结论描述当时阶段，不是当前实现状态。

2026-10-11。结论：现有证据不足以批准歌曲身份，继续返回 `null`。本机定向检查未发现 helper；本次仅下载源码文本，未安装、构建、运行 helper 或访问音乐 app，没有真实网易云元数据样本。

- 来源：`bundleIdentifier` 由 MediaRemote 当前播放进程 PID 经 `NSRunningApplication` 取得；`playing` 来自系统布尔回调；元数据来自另一异步回调。因此 bundle 可用于筛选 `com.netease.163music`，但本机尚未确认，且各字段不是原子快照。[get.m:39–98][get]
- ID：`uniqueIdentifier`、`contentItemIdentifier` 直接透传对应 `kMRMediaRemoteNowPlayingInfo…` 字段；缺字段就省略，没有网易云 song ID 映射、稳定性检查或保证。字段名不能证明其跨歌曲、队列和会话语义。[转换:61–72、194–195][convert]
- 缺失：必需字段检查失败或读取超过两秒，`get` 输出 `null`；可选 ID 缺失不阻止其他元数据返回。因此退出成功、非空 JSON 均不能批准身份。[get.m:100–146][get] [必需字段检查][keys]
- 兼容：上游声称支持 15.4+、Tahoe；实现借系统 Perl 加载自有 framework，再访问私有 MediaRemote。这不是 macOS 26.6.2 本机兼容证据。[adapter 说明:27–33][readme] [CLI 说明:5][cli-readme] [私有接口:77–111][private]
- 分发：CLI 是 Perl 包装器，安装 adapter 脚本、framework 和测试程序；可选用户安装 Homebrew CLI，或批准后随扩展固定版本分发。[安装布局][install] framework 构建覆盖 arm64/x86_64，仅 ad-hoc 签名；未建立公证或正式发布签名证据。维护成本包括私有接口变更、版本固定、双架构与签名验证。[构建:35、71–76][build]
- 许可：adapter 有完整 BSD-3-Clause，二进制分发须保留通知等条件。CLI 声明同许可，但所查提交树无根 LICENSE；正式分发前补齐许可材料。[adapter LICENSE][license] [CLI 文件声明:1–3][cli]

下一步需协调者批准取得固定版本 helper 后，仅执行 `get --no-artwork`，保留 bundle/PID、playing、两个 ID 和必要歌曲元数据；在用户自然播放期间重复采样，结合其确认的原生歌曲 ID，观察同曲、自然换曲及自然重播的对应关系。重复相等只能证明局部稳定，不能替代身份映射；禁止 `test` 或媒体控制命令。缺 ID、来源不符或映射不明即停止接入。标题组合仍未获批准。

源码固定点：adapter `797729d9b16316dc313844476c153d7a107ca0df`；CLI `3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea`。CLI 固定 adapter 子模块为 `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`，本次比对上述读取、转换、字段检查、构建文件内容相同。

[get]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/src/adapter/get.m#L39-L146
[convert]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/src/adapter/now_playing.m#L55-L200
[keys]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/src/adapter/keys.m#L56-L81
[readme]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/README.md#L27-L33
[cli-readme]: https://github.com/ungive/media-control/blob/3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea/README.md#L5-L18
[private]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/src/private/MediaRemote.m#L77-L111
[install]: https://github.com/ungive/media-control/blob/3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea/CMakeLists.txt#L4-L20
[build]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/CMakeLists.txt#L35-L76
[license]: https://github.com/ungive/mediaremote-adapter/blob/797729d9b16316dc313844476c153d7a107ca0df/LICENSE#L1-L28
[cli]: https://github.com/ungive/media-control/blob/3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea/bin/media-control#L1-L25

## 隔离本机验证补充

经协调者批准，使用上述 adapter 固定提交做了一次临时探针构建。源码 HEAD 已核对，上游源码保持原样、BSD 许可保留，未将 helper 纳入项目或安装到系统。本机没有 CMake，因此使用已有 Apple Clang 17.0.0（clang-1700.4.4.1）手工构建；SDK 为 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`，系统为 macOS 26.6.2（25G83）。

构建采用 CMake 中显式 `ADAPTER_SOURCES` 列表，`-dynamiclib -arch arm64 -fobjc-arc -fvisibility=default`，`include` / `src` 搜索路径，链接 Foundation、AppKit、UniformTypeIdentifiers；组装 `Versions/A` framework、Info.plist、公开 header 和 LICENSE 后执行 ad-hoc 签名。签名校验通过，产物仅为 **arm64**，未验证 x86_64，也不代表与上游全部构建属性等价。签名后二进制 SHA-256 为 `72050d06378ccca0538bc8ba076a57bb9d9417e814185acd31a84e301be0567a`。完整命令、布局、工具版本和逐文件摘要已在临时验证记录中交给协调者；未提交二进制或原始输出。

仅运行三次系统 Perl 调用 adapter 的 `get --no-artwork`，间隔三秒；外层限制每次四秒，超时强制结束进程组，stdout 与 stderr 合计上限 64 KiB。未构建或运行 TestClient，未运行其他媒体命令或改变播放、账号、权限。三次耗时分别为 1.492、0.054、0.053 秒，均返回 318 字节、stderr 为空。必要字段三次相同：

| 字段                    | 真实观测                                           |
| ----------------------- | -------------------------------------------------- |
| 来源                    | `com.netease.163music`，PID 5511                   |
| 播放状态                | `playing=false`                                    |
| 曲目信息                | 《恋人》，李荣浩，《黑马》，时长 275.96803125 秒   |
| `uniqueIdentifier`      | 字段缺失，不是显式 `null`                          |
| `contentItemIdentifier` | JSON 字符串 `A3390CFE-7E82-4A22-8809-00E3DA654A78` |

这证明该 arm64 探针能在本机读取一次网易云媒体会话，且字段在此次短时间采样中一致。它不证明 UUID 与原生歌曲 ID 的映射、跨曲／重播稳定性或播放与身份的原子一致性。产品仍保持 `trackKey=null`，未接入 MediaRemote 或真实收藏。

随后协调者提供了用户确认的歌曲 ID `1377163127` 及正在播放 Antisocial 的观测，并授权两次只读窗口检查。本会话仅检查已存在的窗口：网易云前台、一个 `AXStandardWindow`；其 `AXChildren`、`AXChildrenInNavigationOrder`、`AXSections` 均为空，`AXDocument` 不可读，属性列表未暴露 `AXURL`、`AXIdentifier`，窗口标题未包含当前曲名或该歌曲 ID。没有发现可核实的原生歌曲链接或当前播放控件。未打开窗口、点击、读取剪贴板或再次运行媒体 helper；这仅是当前 AX 暴露范围内未找到证据，不证明客户端内部没有歌曲 ID。
