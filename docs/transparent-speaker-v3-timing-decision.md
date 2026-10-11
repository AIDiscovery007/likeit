# V3 跳转与正常推进的时间证据

最终需求 review 在 `badc47e` 发现：显示层允许 250ms 的墙钟残差，可能把可辨认的小幅跨行跳转当作正常入场。例如位置 3.85s，100ms 后跳到 4.10s、下一行起点4.0s，150ms残差仍会保留旧页并淡入。P04要求跳转立即显示最新页，这个问题需修改实现，旧 571 项和 233 文件冻结不变。

真实来源已经提供微秒单位位置、单调采样时间与播放速率。Session每次render用 `elapsed + (now - sampledAt) * rate` 计算可信位置；View观察时刻还含界面调度延迟，不能用它代替来源时刻。单纯收紧墙钟阈值还会误伤0.5／2／4倍速正常推进。

新增最小呈现证据：

```swift
struct DesktopLyricSample: Equatable {
    let position: Double
    let sampledAt: Double
    let rate: Double
}
// DesktopModel.lyricSample: DesktopLyricSample? = nil
```

Session.render只读取一次systemUptime作为now，原可信位置计算及sample发布使用同一now，原lyricPosition接口保留。未知进度、clearDisplayedLyrics、clear、stop清sample。纯文本、纯音乐和首行前如有可信位置仍可提供sample，但不制造cue或四行页。没有第二业务时钟、额外采集或seek事件框架。

View.Input使用sample替代独立position观察，删除observedAt状态。连续性同时要求：门控前后允许；两样本存在；速率相同且>0；采样间隔>0且≤0.5s；位置增量与旧速率×采样间隔的差≤0.005s。再沿用同曲、相邻索引及真正跨越cue.start的条件。缺少证据、速率变化、反向、跳变、gate off时立即移除旧页和过渡，显示最新应显示内容。相同cue内的跳变也中止未完成动画。

5ms是浮点／来源微小校正的容差，不是对底层seek事件精度的承诺。源端没有独立seek标识；容差内的极小变化不能可靠区分，文档必须如实说明。明显跳变不得再借宽容差走顺序动画路径。

协调者在产品改动前新增独立回归：真实Session样本同源／清理，以及真实receive方法的正常／迟观察／倍速／150ms残差／缺样本／变速／同cue中断。开发者不修改或运行测试，现有测试断言和设计冻结不回写。
