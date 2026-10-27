# App 文楷三语字体

2026-10-27：App 及 App 离线预览使用以下同源本地字体。Admin 保持原样。

| 文字 | 字体 | 实际字重 |
|---|---|---|
| 英文、数字及其支持的标点 | Ysabeau Office | 可变 1–1000（界面使用常规字重） |
| 中文 | LXGW WenKai Lite / 霞鹜文楷轻便版 | Regular 400、Medium 500 |
| 韩文 | LXGW WenKai KR | Regular 400、Medium 500 |

渲染顺序为 Ysabeau Office → 文楷 Lite → 文楷 KR → Noto Sans KR → Emoji/系统回退。文楷 Lite 已核对不含现代韩文音节，避免韩文优先命中中文字体；文楷 KR 包含全部11,172个现代韩文音节。Ysabeau Office 采用齐线等宽数字。中文及韩文字重超过500时以已有Medium为基础由平台处理，不包含原生700字重；Flutter可能合成更粗效果，HTML预览禁用合成，粗标题在不同渲染器上可能略有差异。

原资源圆体/Noto Sans SC文件保留在源码中供比较，不列入当前Flutter打包清单。Noto Sans KR继续作为后备；罕见汉字仍需系统回退，不承诺任意字符均有字形。

## 官方来源与校验

所有下载固定到上游提交，未修改TTF字形。采用SIL OFL 1.1；对应版权与完整许可进入App资源和LicenseRegistry，亦随预览存放于licenses/。

| 文件 | 官方固定版本来源 | SHA-256 |
|---|---|---|
| `LXGWWenKaiLite-Regular.ttf` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenKai-Lite/d5a8a1f67872f398ef364a525a77261b3d9ae281/fonts/TTF/LXGWWenKaiLite-Regular.ttf) | `f799a538a3355877e597a0ae04050e897932c9ae7689eb9227c2953c5dd549ea` |
| `LXGWWenKaiLite-Medium.ttf` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenKai-Lite/d5a8a1f67872f398ef364a525a77261b3d9ae281/fonts/TTF/LXGWWenKaiLite-Medium.ttf) | `9282063131640c9558a102560cf6d6f8ecc4bb441e74f2bcff032ce4786238d0` |
| `LXGWWenKai-LICENSE.txt` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenKai-Lite/d5a8a1f67872f398ef364a525a77261b3d9ae281/OFL.txt) | `0333a85fe077b6849f8e417acc44e8bd879442ceb681e271acf93e2d57fd4e2e` |
| `LXGWWenKaiKR-Regular.ttf` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenkaiKR/cbbceb5f5ea82738db40eb996a23a9f980b19723/fonts/TTF/LXGWWenKaiKR-Regular.ttf) | `202395030d07b078dfa5ae8f11f6ab0a5575dd5a49357fa560c319fef39bc5b0` |
| `LXGWWenKaiKR-Medium.ttf` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenkaiKR/cbbceb5f5ea82738db40eb996a23a9f980b19723/fonts/TTF/LXGWWenKaiKR-Medium.ttf) | `3966813554d5a24574f7d90da480835a5a3018b72d41f24c39566d0154edec34` |
| `LXGWWenKaiKR-LICENSE.txt` | [上游文件](https://raw.githubusercontent.com/lxgw/LxgwWenkaiKR/cbbceb5f5ea82738db40eb996a23a9f980b19723/OFL.txt) | `e270ddb6be9ebd4d25c460dcddb7ca2255508ae5ae560c514f2e5b07daed764b` |
| `YsabeauOffice-VF.ttf` | [上游文件](https://raw.githubusercontent.com/google/fonts/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/ysabeauoffice/YsabeauOffice%5Bwght%5D.ttf) | `0f305c8451c1566f0ae62dca9921831fa59f09f6468b012fd6c9161362b5d360` |
| `YsabeauOffice-LICENSE.txt` | [上游文件](https://raw.githubusercontent.com/google/fonts/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/ysabeauoffice/OFL.txt) | `1343b9162a2d24f685767766ea23a75a80b88ba13ba421244e65b72210578b78` |

## 预览重建与验证

Flutter在app/pubspec.yaml注册实际资源，主题统一在app/lib/app_theme.dart配置。预览用同一份TTF转换成WOFF2并内嵌app-fonts.css，file协议不依赖CDN或服务。保留完整字符映射，不按页面文字裁剪。

安装fonttools[woff]后执行：

```bash
python preview/app/build-fonts.py
```

转换脚本校验字符映射、字形轮廓和字重一致；输出CSS必须入库。大字体会增加仓库、App及预览文件体积，本轮未进行包体子集优化。
