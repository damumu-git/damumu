# Admin 文楷三语字体

Admin与App采用同一份字体来源，正文、表格、标题、按钮、输入框和弹窗统一使用：

1. Ysabeau Office：英文、数字及其支持的标点，可变字重1–1000。
2. LXGW WenKai Lite：中文，Regular 400与Medium 500；不包含现代韩文音节。
3. LXGW WenKai KR：韩文，Regular 400与Medium 500。
4. Noto Sans KR及系统字体用于缺字回退。

CSS禁用合成粗体；文楷请求高于500的字重会匹配实际Medium。保留代码/资源标识的
浏览器等宽显示。未改字号、业务逻辑、API或数据库。

## 本地打包和许可

`src/assets/fonts/*.woff2` 随Vite构建导出带哈希的字体文件，CSS使用同源相对地址；
不调用Google Fonts/CDN，也不要求服务器或用户先安装字体。六个文件总计约28MiB，
浏览器按字体使用情况加载并缓存，首次访问需要下载所用字体。

`src/fonts.css` 注册字体，`src/index.css` 定义统一字体顺序，原Georgia设置改为引用
同一字体变量。源TTF版本、SHA-256和官方地址见 `../preview/app/FONTS.md`。
完整SIL OFL版权与许可位于 `public/licenses/fonts/`，构建后仍可从
`/licenses/fonts/` 读取。字体容器转换未改变字形及字符映射。

## 重建

正常的 `npm run build` 和Docker构建直接使用已提交的WOFF2，不需要Python，
也不依赖Docker构建上下文外的App目录。

若更新上游字体，先按App说明重建 `preview/app/app-fonts.css`，再在仓库根目录运行：

```bash
python admin/build-fonts.py
npm --prefix admin run lint
npm --prefix admin run build
```

Admin导出脚本仅需Python标准库：核对源TTF哈希并提取已验证的同源WOFF2、复制许可，
不重复下载或按当前页面裁剪字库。Admin离线预览复用 `preview/app/app-fonts.css`，
与App预览字体一致，无需另存一份大体积内嵌字体。
