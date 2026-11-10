# README 深色页面预览优化

## 原因与改动

透明画布已经存在；原生玻璃壳的深色吸收层叠到 GitHub 深色页面时轮廓对比不足，因此只去背景无法解决。

- 保留原有浅色 PNG／APNG 字节、预览尺寸、双图表格、折叠动图、双语顺序与下载信息。
- 新增四个深色专用原生渲染，使用测试场景里的宽幅冷白环境补光（指数 6），保留原始玻璃材质、图标、相机和透明画布。没有对输出位图调亮或生成虚构产品图，也没有修改应用运行场景。
- 中英文 README 四组图片使用 GitHub 支持的 [`picture` 与 `prefers-color-scheme`](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/quickstart-for-writing-on-github#adding-an-image-to-suit-your-visitors) 选择深／浅资源；默认 `img` 回退到原来的浅色图。
- 仅文档与可选导出工具更新，应用版本和公开安装包仍为 `0.22.6`，用户配置未触碰。

## 验证

```bash
env TCUBE_README_THEME_PREVIEWS=1 swift test --scratch-path .build/tests --no-parallel --filter ReadmeThemePreviewTests
git diff --check
```

- 原生导出 1 项通过；静态 PNG 与动图每一帧均校验透明角落，动图解码为 36 帧，悬停阶段保持旋转暂停。浅色原图 `git diff` 为空。
- Playwright 使用本地 README HTML、GitHub 常见页面配色检查，不冒充线上浏览器实测：1100px／390px，浅／深共四组，均载入 4 个图片，资源源地址正确、动态主题切换通过、页面异常为零。
- 另检查 Dark Dimmed `#22272e` 与常规深色 `#0d1117`；人工查看实际浏览器截图，确认外沿可见、无矩形底色，浅色外观维持原样。展开动图后检查实际帧显示。
- Impeccable 检测返回空问题列表。浏览器截图与导出日志保存在忽略目录 `.build/readme-theme-qa/`、`.build/readme-theme-previews/`。

| 深色资源 | 字节 | SHA-256 |
| --- | ---: | --- |
| `cube-hover-dark.png` | 255885 | `7470eb7284a1e60ce6df5f4489969e0f0a62ca07e390f16ce55d6a812f6a66b8` |
| `cube-idle-dark.png` | 217165 | `911ce82cc4af1ef9d360bb4a57c9ac119d43259a121e63825bdc2a3b49009122` |
| `cube-aurora-dark.png` | 253533 | `ea0cbd4e61a74242fac41e2234033d05644d057e2e28386615313f4ff8655644` |
| `cube-motion-dark.png` | 4035438 | `cd44f7e434f892d95ce0e19e44909e2d3acbb1dd1f00890fd42ab056f9e3f8c5` |
