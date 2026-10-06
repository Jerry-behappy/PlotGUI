"""PlotGUI 的数值处理与配置；不依赖 GUI，可独立验证。"""

from __future__ import annotations

import csv
import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

VERSION = "1.0.0"
EDIT_DATE = "2026-10-06"
DEFAULTS = {
    "geometry": "1440x850", "directory": "", "x_column": 1, "y_column": 3,
    "cal_x_column": 1, "cal_y_column": 3, "cal_file": "",
    "subtract_calibration": False, "smooth": False, "smooth_points": 5,
    "x_factor": 1.0, "y_factor": 1.0, "y_offset": 0.0,
    "xmin": "", "xmax": "", "ymin": "", "ymax": "",
    "x_scale": "linear", "y_scale": "linear", "auto_scale": True,
    "title": "", "xlabel": "Wavelength (nm)", "ylabel": "Loss (dB)",
    "font_size": 18, "legend_font": 12, "legend_columns": 1,
    "legend_location": "best", "bold": True, "legend": True,
    "grid": True, "default_legend": True, "yline": False,
    "line_width": 1.2, "render_mode": "抗锯齿", "watch_files": False,
}


@dataclass
class Curve:
    key: str
    name: str
    x: np.ndarray
    y: np.ndarray
    source: Path | None = None


@dataclass
class Settings:
    values: dict = field(default_factory=lambda: dict(DEFAULTS))
    legends: dict[str, str] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path) -> Settings:
        settings = cls()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return settings
        if not isinstance(payload, dict):
            return settings
        for key, default in DEFAULTS.items():
            value = payload.get("values", {}).get(key, default) if isinstance(payload.get("values"), dict) else default
            if isinstance(default, bool):
                valid = isinstance(value, bool)
            elif isinstance(default, (int, float)):
                valid = isinstance(value, (int, float)) and not isinstance(value, bool) and np.isfinite(value)
            else:
                valid = isinstance(value, str)
            if valid:
                settings.values[key] = value
        for key in ("x_column", "y_column", "cal_x_column", "cal_y_column", "smooth_points", "font_size", "legend_font", "legend_columns"):
            settings.values[key] = max(1, int(settings.values[key]))
        settings.values["legend_columns"] = min(20, settings.values["legend_columns"])
        for key in ("x_scale", "y_scale"):
            if settings.values[key] not in ("linear", "log"):
                settings.values[key] = "linear"
        if settings.values["legend_location"] not in LEGEND_LOCATIONS:
            settings.values["legend_location"] = "best"
        if settings.values["render_mode"] not in ("抗锯齿", "快速"):
            settings.values["render_mode"] = "抗锯齿"
        settings.values["line_width"] = max(0.1, min(20.0, settings.values["line_width"]))
        labels = payload.get("legends", {})
        if isinstance(labels, dict):
            settings.legends = {k: v for k, v in labels.items() if isinstance(k, str) and isinstance(v, str)}
        return settings

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"values": self.values, "legends": self.legends}, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temporary, path)


LEGEND_LOCATIONS = {
    "best": "best", "northeast": "upper right", "northwest": "upper left",
    "southeast": "lower right", "southwest": "lower left", "north": "upper center",
    "south": "lower center", "east": "center right", "west": "center left",
}


def settings_path() -> Path:
    base = Path(os.environ.get("APPDATA", str(Path.home() / ".config")))
    return base / "JNU-MWP" / "PlotGUI" / "settings.json"


def read_numeric(path: Path, max_rows: int | None = None) -> np.ndarray:
    """读取 TXT/CSV/DAT，保留列位置，忽略文本表头；不执行文件中的内容。"""
    try:
        text = path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        text = path.read_text(encoding="gb18030", errors="replace")
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "%", "//")):
            continue
        if "\t" in line:
            tokens = line.split("\t")
        elif "," in line:
            tokens = next(csv.reader([line]))
        elif ";" in line:
            tokens = line.split(";")
        else:
            tokens = line.split()
        row = []
        for token in tokens:
            try:
                row.append(float(token.strip().replace("D", "E").replace("d", "e")))
            except ValueError:
                row.append(np.nan)
        if any(np.isfinite(row)):
            rows.append(row)
            if max_rows is not None and len(rows) >= max_rows:
                break
    if not rows:
        raise ValueError(f"{path.name} 没有可用数值数据")
    data = np.full((len(rows), max(map(len, rows))), np.nan)
    for index, row in enumerate(rows):
        data[index, :len(row)] = row
    return data


def columns(data: np.ndarray, x_column: int, y_column: int) -> tuple[np.ndarray, np.ndarray]:
    if min(x_column, y_column) < 1 or max(x_column, y_column) > data.shape[1]:
        raise ValueError(f"所选 X/Y 列超出文件的 {data.shape[1]} 列")
    x, y = data[:, x_column - 1], data[:, y_column - 1]
    valid = np.isfinite(x) & np.isfinite(y)
    if not valid.any():
        raise ValueError("所选 X/Y 列没有有效数值")
    return x[valid].astype(float), y[valid].astype(float)


def moving_mean(y: np.ndarray, window: int) -> np.ndarray:
    """与 MATLAB movmean 的中心窗口和边缘缩短窗口一致，包括偶数窗口。"""
    y = np.asarray(y, dtype=float)
    window = min(len(y), max(1, int(window)))
    if window <= 1:
        return y.copy()
    index = np.arange(len(y))
    left = np.maximum(0, index - window // 2)
    right = np.minimum(len(y), index + (window - 1) // 2 + 1)
    total = np.concatenate(([0.0], np.cumsum(y)))
    return (total[right] - total[left]) / (right - left)


def sorted_unique(x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    order = np.argsort(x, kind="stable")
    x, y = x[order], y[order]
    x, indices = np.unique(x, return_index=True)
    return x, y[indices]


def process_data(data: np.ndarray, values: dict, calibration: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    x, y = columns(data, int(values["x_column"]), int(values["y_column"]))
    x *= float(values["x_factor"])
    y *= float(values["y_factor"])
    if values["subtract_calibration"]:
        if calibration is None:
            raise ValueError("请选择可用的校准曲线文件")
        cx, cy = columns(calibration, int(values["cal_x_column"]), int(values["cal_y_column"]))
        cx, cy = sorted_unique(cx * values["x_factor"], cy * values["y_factor"])
        if len(cx) < 2:
            raise ValueError("校准曲线至少需要两个不同的 X 点")
        interpolated = np.interp(x, cx, cy, left=np.nan, right=np.nan)
        valid = np.isfinite(interpolated)
        x, y = x[valid], y[valid] - interpolated[valid]
        if not len(x):
            raise ValueError("曲线与校准文件没有重叠的 X 范围")
    y += float(values["y_offset"])
    if values["smooth"]:
        y = moving_mean(y, values["smooth_points"])
    return x, y


def difference(a: Curve, b: Curve, values: dict, key: str) -> Curve:
    xa, ya = sorted_unique(a.x, a.y)
    xb, yb = sorted_unique(b.x, b.y)
    if len(xa) < 2 or len(xb) < 2:
        raise ValueError("每条曲线至少需要两个不同的 X 点")
    at_a = np.interp(xa, xb, yb, left=np.nan, right=np.nan)
    valid = np.isfinite(at_a)
    if not valid.any():
        raise ValueError("曲线 A 和 B 没有重叠的 X 范围")
    y = ya[valid] - at_a[valid]
    if values["smooth"]:
        y = moving_mean(y, values["smooth_points"])
    return Curve(key, f"{a.name} - {b.name}", xa[valid], y)


def visible_data(curve: Curve, xlim: tuple, ylim: tuple) -> tuple[np.ndarray, np.ndarray]:
    x, y = np.asarray(curve.x), np.asarray(curve.y)
    if x.shape != y.shape:
        raise ValueError("曲线 X/Y 点数不一致")
    valid = np.isfinite(x) & np.isfinite(y)
    valid &= (x >= min(xlim)) & (x <= max(xlim)) & (y >= min(ylim)) & (y <= max(ylim))
    return x[valid], y[valid]


def visible_extrema(curves: list[Curve], xlim: tuple, ylim: tuple) -> tuple[float, float] | None:
    bounds = [visible_data(curve, xlim, ylim)[1] for curve in curves]
    bounds = [y for y in bounds if len(y)]
    if not bounds:
        return None
    return max(float(y.max()) for y in bounds), min(float(y.min()) for y in bounds)


def write_visible_csv(folder: Path, name: str, curve: Curve, xlim: tuple, ylim: tuple) -> tuple[Path, int]:
    x, y = visible_data(curve, xlim, ylim)
    if not len(x):
        raise ValueError("当前图窗范围内没有可保存的数据点")
    safe_name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name.strip())
    safe_name = re.sub(r"(?i)\.csv$", "", safe_name).rstrip(". ")[:120] or "processed_curve"
    if re.match(r"(?i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)", safe_name):
        safe_name = "_" + safe_name
    folder.mkdir(parents=True, exist_ok=True)
    for number in range(1, 100000):
        path = folder / f"{safe_name}{'' if number == 1 else '_' + str(number)}.csv"
        try:
            # 独占创建防止覆盖；UTF-8 BOM 方便 Windows Excel 读取。
            with path.open("x", encoding="utf-8-sig", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(["X", "Y"])
                writer.writerows(zip(x, y))
            return path, len(x)
        except FileExistsError:
            continue
    raise OSError("保存文件名已用尽")
