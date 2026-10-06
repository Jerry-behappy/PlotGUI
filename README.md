# PlotGUI 数据绘图GUI

同一套科研数据绘图工具，提供 MATLAB 和 Python 两个版本。用于 TXT、CSV、DAT 曲线的校准、平滑、比较和当前图窗数据导出。

## 选择下载版本

| 版本 | 下载 | 运行条件 |
| --- | --- | --- |
| MATLAB 版 | [PlotGUI-MATLAB.zip](https://github.com/Jerry-behappy/PlotGUI/releases/latest/download/PlotGUI-MATLAB.zip) | MATLAB R2023a 或兼容版本 |
| Python Windows 版 | [PlotGUI-Python-Windows.zip](https://github.com/Jerry-behappy/PlotGUI/releases/latest/download/PlotGUI-Python-Windows.zip) | Windows 10/11 64 位；解压后运行 PlotGUI.exe，无需安装 Python |
| Python 源码版 | [PlotGUI-Python-Source.zip](https://github.com/Jerry-behappy/PlotGUI/releases/latest/download/PlotGUI-Python-Source.zip) | Python 3.10+，Tkinter、NumPy、Matplotlib |

[全部发行版本](https://github.com/Jerry-behappy/PlotGUI/releases)

## 运行

MATLAB：打开 `matlab` 文件夹中的 `Plot_GUI_20260727.m`，运行 `Plot_GUI_20260727`，再选择数据目录。

Python 源码：进入 `python` 文件夹执行：

```powershell
python -m pip install -r requirements.txt
python plot_gui.py
```

也可以执行 `launch.bat`，或直接指定数据目录：

```powershell
python plot_gui.py "D:\MyData"
```

Linux 下如缺少 Tkinter，需要用系统包管理器安装 `python3-tk`。Windows 安装官方 Python 时保留 Tcl/Tk 组件。

## 功能

- 单击文件即可切换选中，多选无需 Ctrl；双击打开可关闭的表格预览。
- 选择作图 X/Y 列、校准文件及校准 X/Y 列。
- 数据先缩放，再插值扣除校准曲线，随后应用 Y 补偿及 smooth；仅使用校准重叠范围。
- 自动 X tight、手动 X/Y 范围、linear/log 尺度。
- 标题、轴标题、字号、线宽、网格、图例位置与列数即时更新；支持编辑图例。
- `yline1 = ymax`、`yline2 = ymin`：从当前 XLim/YLim 窗口内的处理后曲线点计算，标签仅显示数值。
- 保存选中的处理后曲线，只导出当前图窗内的点，CSV 两列为 `X,Y`，自动追加编号避免覆盖。
- 两条当前曲线相减，使用重叠 X 范围和线性插值。
- 图形属性、坐标设置、smooth 点数和窗口大小持久化。
- Python 版支持文件变化自动重绘、嵌入式缩放/平移/图像保存工具栏。

Python 版采用 TkAgg，提供“抗锯齿/快速”模式。MATLAB 版保留 MATLAB 的 opengl/painters 渲染选项。

Python 配置在 Windows 保存至 `%APPDATA%\JNU-MWP\PlotGUI\settings.json`。恢复默认配置时关闭程序并删除该文件。MATLAB 使用 `PlotGUI` 用户偏好组。

MATLAB 版保留 2026-07-27 编辑日期与原函数名；Python 版编辑日期为 2026-10-06。

## 验证与维护

```powershell
python -m unittest discover -s tests -v
python python/plot_gui.py --gui-smoke-test
```

测试覆盖数据列解析、MATLAB movmean 奇偶窗口、校准与缩放顺序、曲线相减、可见区域 yline、截取 CSV、配置恢复及 GUI 关闭。GitHub Actions 在 Windows 上执行这些检查。

主分支采用 PR 合并、自动测试、禁止强推及禁止删除的保护。单人维护不要求额外审批人数，提交者仍需通过 PR 与测试。
