"""生成可分别下载的发布包，按明确文件列表打包源码。"""

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


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
