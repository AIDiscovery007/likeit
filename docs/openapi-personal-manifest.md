# 个人开发者真实清单兼容回归

主会话在用户确认个人开发者入口并手机扫码授权后取得真实CLI manifest。search/song与song/lyric均为GET，`fixed_params` 明确为JSON null，表示无固定参数。f673898产品误判此合法格式为清单不受支持；身份校验及请求安全限制无需改变。

公开描述裁剪样本保存为 acceptance/fixtures/openapi/personal-manifest.json：只保留root的两个资源引用及两个命令描述，无实际凭据、用户资料、token、设备信息或歌曲歌词。

- Given真实清单的search.fixed_params=null，When精确双ID匹配且逐字接口有同步原文，Then经过manifest/search/word共3请求返回原文行。
- Given同一清单的song.lyric.fixed_params=null且逐字返回data=null，When请求普通歌词，Then经过共4请求返回普通原文行。
- Givenfixed_params为123等非对象非null类型，When读取清单，Then在发起search前拒绝。

仅将fixed_params的null视为缺省空对象，不推广到必填字段或任意类型。新增测试由主会话在产品修复前冻结并执行，旧测试和阈值不修改；开发者只修改产品并重建，不编写、修改或运行测试。
