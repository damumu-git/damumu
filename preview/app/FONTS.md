# App 圆体试用

App 和此预览使用同一份 **Resource Han Rounded CN / 资源圆体**，来源为作者的
[v0.990 正式发行](https://github.com/CyanoHao/Resource-Han-Rounded/releases/tag/v0.990)。
采用 `RHR-CN-0.990.7z` 中原始 Regular（400）、Bold（700）TTF；字体文件未修改。
正文使用 Regular，粗标题使用 Bold；中间字重由平台在这两个实际字重中匹配。

原始 TTF SHA-256：

```text
Regular  1c5c623f008eabef10c45135a48b01b46311f9369c28857355872cfe05f48dc0
Bold     f713907a21a10701cd68a7ce3e345ccdce46c789e1809d65ace54e095d7107c3
```

中文与英文优先使用资源圆体。CN 字体不包含韩语谚文，继续用仓库原有 Noto Sans KR
处理韩文，并保留 App 的 Emoji 字体。Admin 的字体未调整。

## 本地与离线

- Flutter：`app/assets/fonts/ResourceHanRoundedCN-{Regular,Bold}.ttf`，在 pubspec
  注册，正式主题通过 `AppTypography.family` 使用；许可也进入 App 资源与许可证登记。
- HTML：`app-fonts.css` 使用完整 Unicode 映射的 WOFF2 内嵌资源，避免 `file://`
  加载外置字体时的跨域限制，不使用 CDN，不需要启动服务。该样式只在 App 入口引用。
- Web 字体由同一份 TTF 转换，未做按页面文字截取的子集，输入其他中文也能使用圆体。
  各源字体的 SHA-256 记录于 CSS 注释。
- 两份完整许可随预览保存在 `licenses/`；源文件来自作者项目的
  [Resource Han Rounded OFL](https://github.com/CyanoHao/Resource-Han-Rounded/blob/master/OFL-License.txt)
  和 Google Fonts 的 [Noto Sans KR OFL](https://github.com/google/fonts/blob/main/ofl/notosanskr/OFL.txt)。

在有 `fonttools[woff]` 的 Python 环境中重建预览字体：

```bash
python preview/app/build-fonts.py
```

脚本验证每个 WOFF2 转换前后的 Unicode 映射、字形轮廓和字重一致，只输出体积和字符数，不连接网络。
必须提交输出的 `app-fonts.css`，使用者直接打开预览即可，无需安装 Python。

字体体积大于系统字体方案；此为已选字体的试用，不代表已经完成移动端包体优化。
原 Noto Sans SC 文件保留在源码中方便比较，但不再列入本轮 Flutter 字体打包清单。
