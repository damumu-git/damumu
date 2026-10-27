# 64px 图标素材与管理

根据 `EMOJI_INVENTORY.md` 的67种字符制作统一低饱和雾蓝、米白、浅棕插画。
每张交付 PNG 为64×64、透明底；全部素材共339,971字节（约332KiB）。
原始大图不进入项目。AI生成来源与提示词见 `restapi/Assets/emoji/generation.json`；
文件名、Emoji、哈希、字节数与存储键见同目录 `manifest.json`。

## 正式服务

- 源文件：`restapi/Assets/emoji/*.png`。API发布时按 `restapi/EmojiAssets.props`
  复制为带内容哈希的 `preset-emoji/<key>-<hash>.png`。
- API启动时仅补齐媒体根目录内缺失的文件，不覆盖运营者上传的文件。
  AWS默认实际位置为 `/srv/damumu/uploads/emoji/`，容器内为
  `/var/lib/damumu/uploads/emoji/`；无需给Admin挂载上传目录。
- 数据库迁移 `023_emoji_assets.sql` 建立 `emoji_asset` 并插入67条素材映射。
  重复执行不会覆盖已替换、改名或停用的素材。保留原分类、兴趣及Emoji值。
- `GET /api/v1/emoji-assets` 返回启用素材；分类/兴趣新增 `icon_url`，
  活动及活动记录新增 `category_icon_url`。URL使用既有 `Media:PublicBaseUrl`
  转成完整API媒体地址，例如 `https://api.damumu.com/uploads/emoji/<key>-<hash>.png`。
- 分类先匹配已有 `icon_key` 指定的启用素材，未匹配则按原Emoji匹配；变体选择符
  U+FE0E/U+FE0F不影响对应关系。不在客户端硬编码生产分类。
- App的分类、活动封面回退、活动记录、群聊/私信标识、喜欢计数显示图片。
  全局图标目录在启动及回到前台时刷新；接口失败或未知图标保留原字符回退。
  不替换用户聊天正文、昵称，也不替换正式JPEG系统头像。

## Admin操作

侧栏“图标素材”支持搜索、上传新素材、替换图片、修改名称、启停。
分类编辑器的“图标素材”可选择资源键；留空按原Emoji自动匹配。

- 上传仅接受静态64×64 PNG，最大200KiB；服务器解码并重新编码。
- 已有资源键及对应Emoji不可改动；需新增对应关系时创建新资源。
- 只改名称无需重新上传图片。替换停用素材不会自动启用。
- 每次替换分配新文件名，避免一年immutable缓存继续显示旧图；旧版本保留以兼容
  已缓存或仍打开的页面。当前不提供物理删除，启停及上传写入审计日志。
- 沿用现有管理员认证与Admin域名保护；公共接口没有写入能力。

## 离线预览

App/Admin预览通过 `preview/shared/emoji-artwork.js` 内嵌同源小PNG，
直接打开HTML即可，无CDN、API请求或额外服务。新增Admin入口
`preview/admin/index.html#emoji-assets` 可查看完整图册；其中明确标注模拟预览，
实际上传和启停在正式Admin执行。选项编辑等需要保留字符身份的输入不做图片化。

## AWS部署顺序

本次没有连接AWS或执行线上迁移。合并main后按既有部署流程：

1. 在服务器运行 `damumu-deploy` 拉取代码；检测到023时会暂停。
2. 备份数据库，核对当前角色及数据库名，再用具备建表权限的迁移角色执行023。
   必须确保022等此前迁移均已应用；不要用部署标志替代SQL执行。
3. SQL成功后运行 `damumu-deploy --migrations-applied` 重建API/Admin。
   API启动自动把预设小图补入现有持久化目录，不需要重新迁移旧图片卷。
4. 检查公共图标目录、任一返回的图片URL及后台素材列表。移动App需重新构建发布。

## 验证与后续素材

```bash
python restapi/tests/check_emoji_assets.py
dotnet build restapi/Muda.Api.csproj
cd app && flutter analyze && flutter test
cd ../admin && npm run lint && npm run build
```

`restapi/tests/emoji_assets_api.py` 只允许localhost，需专用可丢弃数据库与API，
会停用/替换测试图标，不得对线上使用。`admin/check-emoji.cjs <jsdom目录>`
验证构建后React界面的11个入口、分类选择与素材管理表单；不访问网络。

新增图标优先通过Admin上传。若要把新图标做成仓库默认预设，应制作新的顺序迁移，
同步manifest、发布路径及离线图册；不得重写已上线的023或覆盖现有版本文件。
