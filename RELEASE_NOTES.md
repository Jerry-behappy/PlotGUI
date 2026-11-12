# PlotGUI v1.1.0 — 新增 Web 离线版

- 新增 `PlotGUI-Web.html`：包含全部绘图库、处理逻辑和样式，下载后用 Edge/Chrome 直接打开，无需联网、服务器、Python 或 MATLAB。
- 新增 `PlotGUI-Web.zip`：离线单文件与可编辑 HTML/CSS/JS、运行库许可证及中文使用说明。
- 支持选择文件夹、拖入文件或文件夹、本机读取 TXT/CSV/DAT、列选择、校准扣除、缩放补偿、smooth、曲线相减与 A/2+B/2 运算。
- 支持可见窗口 yline、最大值星号及图下分析；PNG 复制为图片，SVG 和可见窗口 CSV 复制为文本。
- 平移、缩放、Autoscale 不回写作图设置；样式设置保存在本机浏览器。
- 原始数据不上传、不打包；本次发布不部署线上站点。
- MATLAB 与 Python 源码提供于本版附件。Windows 程序未重新编译，请下载 [v1.0.0 Windows 版](https://github.com/Jerry-behappy/PlotGUI/releases/download/v1.0.0/PlotGUI-Python-Windows.zip)；程序内部版本仍为 1.0.0。

## 使用方法

直接下载 `PlotGUI-Web.html` 后用浏览器打开，或下载 `PlotGUI-Web.zip`、解压并双击其中的同名文件。选择文件夹或拖入测试文件即可作图。刷新页面后需要重新导入数据；剪贴板受浏览器限制时按弹窗提示手动复制。

---

# PlotGUI v1.0.0

提供独立 MATLAB 与 Python 下载包。

- MATLAB：2026-07-27 最新绘图 GUI，保留原有函数和功能。
- Python：2026-10-06 Tkinter + Matplotlib 重写，提供源码和 Windows 64 位程序。
- 多选、表格预览、校准数据列、smooth、Y 补偿、图例编辑、曲线相减。
- yline 跟随当前可见数据和实时参数变化。
- CSV 仅保存当前图窗截取的数据。
- 配置与窗口大小持久化。

Windows 版解压后双击 `PlotGUI.exe`，请保留同目录的 `_internal` 文件夹。
