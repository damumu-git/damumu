# App Noto Sans 字体

2026-11-02：正式 Flutter App 与 App 离线预览改用本地 Noto Sans SC / KR。
中文、英文、数字使用 Noto Sans SC，韩文回退到 Noto Sans KR。
两者支持100–900可变字重；SC不含现代韩文音节，KR覆盖全部11,172个现代韩文音节。
Flutter另保留Noto Emoji与系统缺字回退，不承诺覆盖所有Unicode字符。
Admin此前已独立使用同样两套Noto字体，本轮不更改Admin字体或样式。

字体切换只改变字形及排版度量，不修改业务、配色或Logo。旧文楷、圆体和Ysabeau源文件
保留作为历史素材，但不再列入Flutter打包清单或预览CSS，不参与当前字体回退。

## 来源与许可

使用仓库已有原始TTF，与Admin使用的源文件相同；没有重新下载或修改字形。
官方项目：[Noto CJK Sans](https://github.com/notofonts/noto-cjk/tree/main/Sans)。
SIL OFL 1.1完整许可进入Flutter资源及LicenseRegistry，离线预览另附于licenses/。

| 文件 | SHA-256 |
|---|---|
| NotoSansSC-VF.ttf | `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964` |
| NotoSansKR-VF.ttf | `9e1d729e7e2b36f9ef439da102f8c134c10aabe46f1c843bf0aca5c043b86f76` |

## 预览重建与验证

Flutter在`app/pubspec.yaml`注册字体，主题统一在`app/lib/app_theme.dart`配置。
预览从同一TTF转换成WOFF2并内嵌`app-fonts.css`，可离线打开，不依赖CDN。
完整保留字符映射与字形，不按当前页面文字裁剪。

安装fonttools[woff]后，从仓库根目录执行：

```bash
python preview/app/build-fonts.py
```

脚本检查字符映射、字形轮廓及字重一致；生成的CSS需要提交。WOFF2两份合计约13.9MiB，
内嵌CSS约18.6MiB。更新后需重新构建App；已安装的旧版不会自动切换字体。
