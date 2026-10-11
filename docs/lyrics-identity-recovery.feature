Feature: 优先取得可读歌词
  Scenario: 无关坏记录不遮住原曲
    Given 网易返回正确原曲和缺少专辑的无关混剪
    When 我打开歌词桌面
    Then 取得原曲歌词并显示实际来源
  Scenario Outline: 缺少辅助信息仍可取得歌词
    Given 当前歌曲有曲名而缺少<字段>
    When 精确路径不可用
    Then 按曲名和已知歌手继续检索
    And 专辑和时长只用于候选排序
    Examples:
      | 字段 |
      | 专辑 |
      | 时长 |
      | 歌手 |
      | 歌手、专辑、时长和内容ID |
  Scenario: 自动尝试来源和候选
    Given 网易或第一候选没有歌词
    When 串行的AMLL、LRCLIB或同来源下一候选有歌词
    Then 展示可用歌词及实际来源和候选身份
    And 查询顺序为网易、AMLL、LRCLIB且成功即停止
    And 已配置官方但失败时可以去社区而不暗中转网易公开
  Scenario: 没有播放时间也能读
    Given 已取得同步歌词但播放时间未知
    Then 静态展示全文而不伪造同步高亮或进度
  Scenario: 再次打开不用重新匹配
    Given 同一输入和固定串行策略已成功缓存
    When 我退出并重新打开
    Then 在发起网络请求前显示缓存歌词
    And 标记本地缓存
  Scenario: 不串歌且最终结果诚实
    Given 正在获取旧歌或所有来源不可用
    When 换歌、取消或者达到整体时限
    Then 旧结果不能覆盖新歌且失败不缓存
    And 三个来源全无结果才显示暂时没有匹配的歌词
    And 明确不同曲名或已知歌手的歌词不冒充当前歌
