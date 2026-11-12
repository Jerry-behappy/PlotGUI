"""生成可分别下载的发布包，按明确文件列表打包源码。"""

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from web.package_web import build_single_file


WEB_FILES = [
    'index.html', 'style.css', 'plot_core.js', 'app.js', 'clipboard.js',
    'package_web.py', 'README.md', 'vendor/plotly.min.js',
    'vendor/LICENSE-plotly.txt', 'vendor/plotly.min.js.LICENSE.txt',
]


def package_web(root: Path, output: Path) -> None:
    single = build_single_file(output / 'PlotGUI-Web.html')
    with ZipFile(output / 'PlotGUI-Web.zip', 'w', ZIP_DEFLATED) as archive:
        for name in WEB_FILES:
            archive.write(root / 'web' / name, 'PlotGUI-Web/' + name)
        archive.write(single, 'PlotGUI-Web/PlotGUI-Web.html')
        archive.writestr('PlotGUI-Web/开始使用.txt',
                         'PlotGUI Web 离线版\n\n'
                         '双击 PlotGUI-Web.html，用 Edge 或 Chrome 打开即可。\n'
                         '该文件已包含全部运行代码，无需联网、Python、MATLAB 或本地服务器。\n'
                         '也可打开 index.html，但需保留整个文件夹。\n'
                         '支持选择文件夹、拖入 TXT/CSV/DAT，数据仅在本机浏览器处理。\n'
                         '普通导入的数据在刷新后需重新选择，样式设置保存在当前浏览器。\n'
                         'PNG 复制为图片，SVG 复制为源码，数据复制为当前可见窗口的 CSV。\n'
                         '浏览器限制剪贴板时，请按弹窗提示手动复制。\n')
    print('PlotGUI-Web.html')
    print('PlotGUI-Web.zip')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--windows", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    args.output.mkdir(parents=True, exist_ok=True)
    packages = {
        "PlotGUI-MATLAB.zip": ["matlab/Plot_GUI_20260727.m", "README.md"],
        "PlotGUI-Python-Source.zip": ["python/plot_gui.py", "python/plot_core.py", "python/requirements.txt", "python/launch.bat", "README.md"],
    }
    for name, files in packages.items():
        with ZipFile(args.output / name, "w", ZIP_DEFLATED) as archive:
            for file in files:
                archive.write(root / file, file)
        print(name)
    package_web(root, args.output)
    if args.windows:
        if not (args.windows / "PlotGUI.exe").is_file():
            raise FileNotFoundError("Windows 构建缺少 PlotGUI.exe")
        with ZipFile(args.output / "PlotGUI-Python-Windows.zip", "w", ZIP_DEFLATED) as archive:
            for file in sorted(args.windows.rglob("*")):
                if file.is_file():
                    archive.write(file, Path("PlotGUI") / file.relative_to(args.windows))
            archive.write(root / "README.md", "PlotGUI/README.md")
        print("PlotGUI-Python-Windows.zip")


if __name__ == "__main__":
    main()
