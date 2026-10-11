# 音频恢复与权限误报验收

产品最终提交：`23ffa7a242c47ee0a4110f361ffb002e4357c837`。冻结基线：`9fc1043e3d44a42908de2d0dcc0a1a354d1593a9`。

## 结论

恢复与诊断修复通过本轮代码审查、267项自动验收和真实音频启动/退出检查，已经安装到本机Raycast。跨版本授权稳定性尚未验收：本机无有效代码签名身份，当前产物仍是ad-hoc。构建支持固定身份不等于已经配置固定身份，更不等于“一劳永逸”。已向用户确认是否新增本机专用签名身份；尚未创建证书、私钥或改动钥匙串/TCC。

## 原因与改动

- 用户截图是应用的统一失败文案。原实现将超过2秒PCM中断、tap无效句柄以及普通HAL错误全部锁存失败，后续状态刷新统一提示权限/设备异常，用户只能退出重开。协调者在未改生产代码的情况下重放断流与路由错误，得到相同提示和恢复失败，见`review-evidence/immersive-2026-10-11/audio-interruption-red.json`。
- 本机日志于06:22:03记录`AudioHardwareCreateProcessTap: Tap object not found: 3041 with timeout 1001`。这证明tap创建异常，不能据此推断用户拒绝TCC。未取得足以将本次超时归因于签名或授权的证据。
- 断流现只归零并等待，PCM恢复后继续律动。实际启动错误保持有界；普通刷新不自动重试，用户可在桌面内主动重试。IOProc与旧会话回调有epoch隔离。普通错误提示不再冒充权限拒绝，统一日志保留固定失败阶段和OSStatus/无效结果，不记录音频、歌曲或凭据。
- 构建支持`LIKEIT_DESKTOP_SIGNING_IDENTITY`，同身份签framework/app；显式身份无效时失败，不回退。清单记录实际签名类型及两种架构的DR。默认ad-hoc保留开发兼容性并提示授权延续风险。

## 独立验收

- 最终SHA全套`node --test acceptance/*.test.mjs`：267/267通过，0失败、跳过或取消。包含原245项与新增21项行为检查及其父测试。最终原/新音频套件亦独立39/39通过。开发者未写、修改、编译或运行测试。
- 17份冻结清单、72项文件摘要完整；没有修改旧验收或降低断言。10项源码摘要、10项bundle文件摘要与最终清单一致；安装版10项文件与产物一致，严格深层签名验证通过。构建与lint通过。
- 显式空身份、`-`、不存在身份三种签名配置均构建失败，原app和manifest内容保持不变。
- 首次UI观察出现旧提示，未计作新版通过。随后正常退出并确认没有桌面进程，核对安装摘要后打开最终版本。`Designer — Graham`播放中，真实界面显示“网易云实时音频律动”；此文案只由非零真实音频分析结果产生。本轮未出现新的系统授权提示。Esc退出后通过进程检查确认桌面已结束；未用可能重新启动应用的UI读取代替退出检查。
- 验收仅打开/退出Likeit，临时URL指定`mode=always`，未修改持久动效设置，也未调用网易云播放、暂停、切歌或收藏动作。

## Standards

独立标准审查在934c07a发现1项P2：IOProc新增epoch校验调用阻塞式intentLock，与非阻塞音频回调约定不符。23ffa7a改为try-lock争用丢帧，复核确认关闭；普通监听、计时器和发布仍保留完整epoch校验。无剩余已确认标准缺陷。

## Spec

独立需求审查未发现已确认遗漏、范围扩张或实现错误。模拟HAL覆盖断流恢复、三类失败后主动重试、健康/隐藏/退出门禁。真实启动失败时按钮点击恢复没有自然样本，尚未做真实故障注入；多设备切换、长期运行、固定身份两次构建之间的授权延续也未验收。

标准轨原1项已关闭；需求轨0项已确认缺陷。未把上述实机覆盖缺口包装为通过。

## 签名证据

安装版此前的DR仅包含架构cdhash，本机`security find-identity -v -p codesigning`为0项有效身份。固定bundle ID、路径和hardened runtime不能替代固定签名者；Apple说明ad-hoc身份无法可靠跨版本保持隐私权限：[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。本机开发可使用持续复用的自签名身份，但它不是正式分发证书，仍须实际验证当前macOS授权延续：[Apple Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)。
