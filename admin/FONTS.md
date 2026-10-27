# Admin 中文友好无衬线字体

Admin正式界面与离线Admin预览采用Noto Sans SC中文及Noto Sans KR韩文，
两者均为100–900可变字重，包含英文与数字；系统无衬线字体作为后备。
App继续使用原文楷方案。字体不再与App预览捆绑读取。

## 来源与许可

源字体为仓库已有 `app/assets/fonts/NotoSansSC-VF.ttf` 及 `NotoSansKR-VF.ttf`。
字体内版权声明与随附SIL OFL 1.1许可一致（Adobe，Reserved Font Name Source）。
完整许可保存在 `public/licenses/fonts/`，Vite构建复制到 `/licenses/fonts/`；
离线预览另附许可于 `preview/admin/licenses/`。

官方项目说明：[Noto CJK Sans](https://github.com/notofonts/noto-cjk/tree/main/Sans)。
使用的是可读性优先的无衬线字体，保留完整字库，不按现有页面文字裁剪。

| 原始文件 | SHA-256 |
|---|---|
| NotoSansSC-VF.ttf | `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964` |
| NotoSansKR-VF.ttf | `9e1d729e7e2b36f9ef439da102f8c134c10aabe46f1c843bf0aca5c043b86f76` |

## 构建和离线预览

`src/fonts.css` 注册两份WOFF2，`src/index.css` 定义统一字体顺序。
Vite输出独立哈希字体文件；无字体CDN或服务器字体安装要求。
两份WOFF2合计约13.9MiB，浏览器按需加载并缓存。

正常 `npm run build` / Docker构建使用已提交资源，不运行Python。
更新字体时在有fonttools[woff]的Python环境中执行：

```bash
python admin/build-fonts.py
npm --prefix admin run build
```

脚本转换同源TTF为WOFF2，同时核对字符映射、轮廓、字重与可变轴一致，
并生成 `preview/admin/admin-fonts.css` 的内嵌字库，file协议下也无需网络。
SC字库30890字符、KR字库23174字符；罕见字符仍保留系统字体回退。
