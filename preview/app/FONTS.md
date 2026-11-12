# 搭慕用户端字体

Flutter App、App 离线预览和 `app.damumu.com` 使用简体中文版资源圆体（Resource Han Rounded CN）。
中文、英文和数字使用 Regular / Bold，韩文使用 Noto Sans KR。Flutter 同时使用 Noto Emoji 和系统后备字体。

## 来源与许可

字体源文件位于 `app/assets/fonts/`。SIL OFL 1.1 许可随 Flutter 和网页打包，离线预览的许可位于 `licenses/`。
[资源圆体](https://github.com/CyanoHao/Resource-Han-Rounded) · [Noto CJK Sans](https://github.com/notofonts/noto-cjk/tree/main/Sans)

| 文件 | SHA-256 |
|---|---|
| ResourceHanRoundedCN-Regular.ttf | `1c5c623f008eabef10c45135a48b01b46311f9369c28857355872cfe05f48dc0` |
| ResourceHanRoundedCN-Bold.ttf | `f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3` |
| NotoSansKR-VF.ttf | `9e1d729e7e2b36f9ef439da102f8c134c10aabe46f1c843bf0aca5c043b86f76` |

## 预览重建与验证

Flutter在`app/pubspec.yaml`注册字体，主题统一在`app/lib/app_theme.dart`配置。
脚本从同一 TTF 转换 WOFF2，完整保留字符映射与字形。离线预览内嵌 `app-fonts.css`，
独立网页版使用 `app-web/site/assets/fonts/` 中的两份资源圆体 WOFF2。

安装fonttools[woff]后，从仓库根目录执行：

```bash
python preview/app/build-fonts.py
```

脚本核对字符映射、字形轮廓及字重。生成的 CSS 和两份网页 WOFF2 随源代码提交。
更新字体后需重新构建 App 安装包和网站镜像。
