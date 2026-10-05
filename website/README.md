# Damu 静态官网

品牌：搭慕 / 담우 / Damu。默认中文，共 15 个静态 HTML 页面。
所有页面提供中文、English、한국어 切换；换语言保持当前页面。

部署只需上传 `dist/` 的全部内容到 Nginx/Lightsail 或 S3 静态托管。
不需要线上 Python、Node、数据库或 API。域名目标为 `https://www.damumu.com`。
当前未发布到公网。

## 维护

`build_site.py` 保存三语文案和共享模板。修改后运行 `python3 website/build_site.py`，
再运行 `python3 website/check_site.py`。部署产物已生成，不运行脚本也能直接使用。

- 默认文件：`index.html`、`privacy.html`、`terms.html`、`account-deletion.html`、`support.html`。
- 英文加 `-en`，韩文加 `-ko`，如 `privacy-ko.html`。
- `styles.css` 保留品牌主题，`languages.css` 处理三语布局，`script.js` 为移动导航。
- 商店地址尚未提供，下载按钮禁用，二维码仅为明确不可扫描的占位。
- `docs/PRIVACY_REVIEW.md` 记录真实代码核对、保存期限建议、验证边界及待确认清理方案。

## 发布前状态

公开文案仍为政策草案；生效日期、第三方跨境详情及定期删除/备份方案未落实。
App/API 支持密码复核的删除申请与停用；最终清理未完成，不能称为完整数据擦除。
不应直接作为正式商店审核政策使用。手机及 Google 登录未实现，MVP1 不开放 SOS。

已有旧 ZIP 是第一版归档；最新包名为 `damu-trilingual-2026-10-05.zip`。
