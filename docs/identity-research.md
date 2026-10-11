# 歌曲身份只读评估

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
