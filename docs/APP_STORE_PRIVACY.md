# App Store 隐私提交清单

最后核对：2026-10-15（Asia/Seoul）。本清单根据当前代码数据流整理，用于填写 App Store Connect；最终答案必须与待提交版本、服务端行为和第三方 SDK 实际情况一致。

2026-10-21补充：最低年龄改为14岁自我确认，不应再声明仅成年人。新版App默认关闭外部FCM/Nominatim，发布前须核对实际启用状态后填写申报。个人运营者姓名未获公开授权；Apple个人账号及Google Play个人账号的实名展示要求仍需解决。三个月保留、私密图片与运维要求见`PRIVACY_OPERATIONS.md`，不可继续使用“所有历史已完全匿名化”的表述。

## Privacy Policy URL

- 中文：`https://www.damumu.com/privacy.html`
- 韩文：`https://www.damumu.com/privacy-ko.html`
- 网页账号删除说明：`https://www.damumu.com/account-deletion.html`
- 提交审核前必须确认两个地址无需登录即可公开访问。
- 隐私联系邮箱已确定为 `damumuapp@gmail.com`；运营主体名称和具体保存期限仍需确认后写入两个页面。

## 当前可能需要申报的数据类型

| App Store 数据类别 | 当前用途 | 与身份关联 | 用于跟踪 |
| --- | --- | --- | --- |
| Contact Info：Email Address、Name | 注册、登录、昵称和资料展示 | 是 | 否 |
| Location：Precise Location、Coarse Location | 附近活动、距离和地区显示 | 是 | 否 |
| User Content：Photos or Videos、Emails or Text Messages、Other User Content | 头像、活动封面、聊天图片与文字、活动和报名内容 | 是 | 否 |
| Identifiers：User ID、Device ID | 账号关联、认证、FCM 推送设备令牌 | 是 | 否 |
| Usage Data：Product Interaction | 活动浏览、发布、报名、参加、评价和通知状态 | 是 | 否 |
| Diagnostics：Other Diagnostic Data | 必要请求日志和故障排查 | 视生产日志配置核实 | 否 |
| Other Data | 举报、屏蔽、安全确认及治理记录 | 是 | 否 |

当前没有广告 SDK 或跨 App／网站跟踪功能；除非最终构建或第三方 SDK 行为发生变化，不应申报 Tracking。

## 审核前必须完成

- App 设置页可直接发起账号删除，并有明确的二次确认；`DELETE /api/v1/me` 会在单个数据库事务内立即删除认证、资料、兴趣、推送、通知和安全联系人数据，并对有限期保留的活动、会话和治理历史作去标识处理。
- 部署网站后验证 `/account-deletion.html` 可公开访问，并确认邮箱请求的 7 日处理承诺具备实际运营流程。
- 为中、英、韩三种语言核对相机、定位、相册权限说明。
- 在 macOS/Xcode 生成 Release Archive，检查 Privacy Report、`PrivacyInfo.xcprivacy`、Required Reason API 和第三方 SDK 签名；Windows 环境不能完成这项验证。
- 用最终生产配置核对 Firebase、日志、崩溃收集、分析和广告 SDK，确保 App Store Connect 回答没有漏项。
- 在 App Store Connect 为每个数据类型填写收集目的，并发布 App Privacy 回答。
