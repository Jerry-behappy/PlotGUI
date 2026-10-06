"""数据绘图 GUI。Copyright (c) 2026 Junyi Zhang, JNU MWP."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import sys
import tkinter as tk
from tkinter import filedialog, ttk

import matplotlib
matplotlib.use("TkAgg")
from matplotlib import font_manager
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.figure import Figure
import numpy as np

from plot_core import (
    Curve, DEFAULTS, EDIT_DATE, LEGEND_LOCATIONS, Settings, VERSION,
    difference, process_data, read_numeric, settings_path, visible_extrema, write_visible_csv,
)

DATA_KEYS = {
    "x_column", "y_column", "cal_x_column", "cal_y_column", "cal_file",
    "subtract_calibration", "smooth", "smooth_points", "x_factor", "y_factor", "y_offset",
    "default_legend",
}
AXIS_KEYS = {"xmin", "xmax", "ymin", "ymax", "x_scale", "y_scale", "auto_scale"}


def title_math(text: str) -> str:
    if "$" in text:
        return text
    return re.sub(r"[A-Za-z0-9]+(?:[_^](?:\{[^{}]*\}|[A-Za-z0-9]))+", lambda match: f"${match.group()}$", text)


class ScrollPanel(ttk.Frame):
    def __init__(self, parent, title):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, highlightthickness=0, background="#f5f6f7", width=200)
        scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.inner = ttk.LabelFrame(self.canvas, text=title, padding=10)
        self.window = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", lambda _: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda event: self.canvas.itemconfigure(self.window, width=event.width))


class PlotGUI:
    def __init__(self, root: tk.Tk, folder: Path | None = None, config: Path | None = None):
        self.root = root
        self.config = config or settings_path()
        self.settings = Settings.load(self.config)
        self.closed = False
        self.updating = True
        self.rendering = False
        self.curves: list[Curve] = []
        self.recipes: list[tuple[str, str, str]] = []
        self.lines = {}
        self.yline_artists = []
        self.jobs = {}
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="PlotGUI-reader")
        self.future = None
        self.generation = 0
        self.pending_load = None
        self.data_cache = {}
        self.file_stamps = {}
        self.preserve_view = None
        self.vars = {}
        for key, value in self.settings.values.items():
            variable = tk.BooleanVar if isinstance(value, bool) else tk.StringVar
            self.vars[key] = variable(root, value=value)
        saved_folder = self.settings.values["directory"]
        default_folder = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
        self.folder = folder or (Path(saved_folder) if saved_folder and Path(saved_folder).is_dir() else default_folder)
        self.vars["directory"].set(str(self.folder))
        self.root.title("数据绘图GUI")
        self.root.minsize(1120, 680)
        try:
            self.root.geometry(self.settings.values["geometry"])
        except tk.TclError:
            self.root.geometry(DEFAULTS["geometry"])
        style = ttk.Style(root)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("TFrame", background="#f5f6f7")
        style.configure("TLabel", background="#f5f6f7", font=("Microsoft YaHei UI", 10))
        style.configure("TLabelframe", background="#f5f6f7")
        style.configure("TLabelframe.Label", font=("Microsoft YaHei UI", 10, "bold"))
        style.configure("TCheckbutton", background="#f5f6f7", font=("Microsoft YaHei UI", 10))
        style.configure("TButton", font=("Microsoft YaHei UI", 10), padding=(7, 5))
        style.configure("Plot.TButton", foreground="white", background="#2670b5", font=("Microsoft YaHei UI", 11, "bold"))
        available_fonts = {font.name for font in font_manager.fontManager.ttflist}
        for font in ("Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Arial Unicode MS"):
            if font in available_fonts:
                matplotlib.rcParams["font.sans-serif"] = [font, "DejaVu Sans"]
                break
        matplotlib.rcParams["axes.unicode_minus"] = False
        self.build()
        self.updating = False
        for key, variable in self.vars.items():
            if key not in ("directory", "geometry"):
                variable.trace_add("write", lambda *_args, k=key: self.changed(k))
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.bind("<Configure>", self.resized)
        self.refresh_files()
        self.render()
        self.after("watch", 1000, self.watch_files)

    def after(self, key, delay, callback):
        previous = self.jobs.pop(key, None)
        if previous:
            self.root.after_cancel(previous)
        if self.closed:
            return
        def invoke():
            self.jobs.pop(key, None)
            if not self.closed:
                callback()
        self.jobs[key] = self.root.after(delay, invoke)

    def status(self, text, error=False):
        if not self.closed:
            self.status_label.configure(text=text, foreground="#a62b2b" if error else "#255c42")

    def entry(self, parent, row, label, key, choices=None, column=0, span=1):
        ttk.Label(parent, text=label).grid(row=row, column=column, sticky="w", pady=4, padx=(0, 5))
        if choices:
            widget = ttk.Combobox(parent, textvariable=self.vars[key], values=choices, state="readonly", width=8)
        elif isinstance(DEFAULTS[key], (float, int)):
            increment = 0.1 if isinstance(DEFAULTS[key], float) else 1
            lower = 1 if isinstance(DEFAULTS[key], int) else -1e12
            widget = ttk.Spinbox(parent, textvariable=self.vars[key], from_=lower, to=1e12, increment=increment, width=8)
        else:
            widget = ttk.Entry(parent, textvariable=self.vars[key], width=12)
        widget.grid(row=row, column=column + 1, columnspan=span, sticky="ew", pady=4)
        parent.columnconfigure(column + 1, weight=1)
        return widget

    def check(self, parent, row, label, key, column=0, span=2):
        widget = ttk.Checkbutton(parent, text=label, variable=self.vars[key])
        widget.grid(row=row, column=column, columnspan=span, sticky="w", pady=5)
        return widget

    def build(self):
        outer = ttk.Frame(self.root, padding=(10, 8))
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text=f"By Junyi Zhang, JNU MWP | 最新修改：{EDIT_DATE}", font=("Microsoft YaHei UI", 14, "bold"), foreground="#465765").pack(anchor="e", pady=(0, 8))
        main = ttk.Panedwindow(outer, orient="horizontal")
        main.pack(fill="both", expand=True)
        files = ttk.LabelFrame(main, text="文件与绘图", padding=10)
        axes_panel = ScrollPanel(main, "坐标设置")
        process_panel = ScrollPanel(main, "数据处理")
        right = ttk.Frame(main)
        for pane, weight in ((files, 1), (axes_panel, 1), (process_panel, 1), (right, 4)):
            main.add(pane, weight=weight)
        files.columnconfigure(0, weight=1)
        files.rowconfigure(3, weight=1)
        ttk.Label(files, text="数据目录").grid(row=0, column=0, sticky="w")
        folder_row = ttk.Frame(files)
        folder_row.grid(row=1, column=0, sticky="ew", pady=(5, 10))
        folder_row.columnconfigure(0, weight=1)
        ttk.Entry(folder_row, textvariable=self.vars["directory"], state="readonly", width=20).grid(row=0, column=0, sticky="ew")
        ttk.Button(folder_row, text="选择…", command=self.choose_folder).grid(row=0, column=1, padx=(5, 0))
        ttk.Label(files, text="作图文件（可多选）").grid(row=2, column=0, sticky="w", pady=(0, 5))
        list_frame = ttk.Frame(files)
        list_frame.grid(row=3, column=0, sticky="nsew")
        self.file_list = tk.Listbox(list_frame, selectmode="multiple", exportselection=False, width=28, height=20, font=("Microsoft YaHei UI", 10), activestyle="none", selectbackground="#2878bd", relief="solid", borderwidth=1)
        scroll = ttk.Scrollbar(list_frame, command=self.file_list.yview)
        self.file_list.configure(yscrollcommand=scroll.set)
        self.file_list.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        self.file_list.bind("<<ListboxSelect>>", lambda _: self.request_data())
        self.file_list.bind("<Double-Button-1>", self.preview)
        commands = ttk.Frame(files)
        commands.grid(row=4, column=0, sticky="ew", pady=8)
        for column, (text, command) in enumerate((("全选", self.select_all), ("清空", self.clear_selection), ("刷新", self.refresh_files))):
            commands.columnconfigure(column, weight=1)
            ttk.Button(commands, text=text, command=command).grid(row=0, column=column, sticky="ew", padx=2)
        data_columns = ttk.Frame(files)
        data_columns.grid(row=5, column=0, sticky="ew")
        self.entry(data_columns, 0, "X 列", "x_column")
        self.entry(data_columns, 1, "Y 列", "y_column")
        ttk.Button(files, text="绘图", style="Plot.TButton", command=lambda: self.request_data(reset_view=True)).grid(row=6, column=0, sticky="ew", pady=(10, 0))
        self.check(files, 7, "文件变化自动重绘", "watch_files")
        axis = axes_panel.inner
        for row, (text, key) in enumerate((("X 最小", "xmin"), ("X 最大", "xmax"), ("Y 最小", "ymin"), ("Y 最大", "ymax"))):
            self.entry(axis, row, text, key)
        self.entry(axis, 4, "X 尺度", "x_scale", ("linear", "log"))
        self.entry(axis, 5, "Y 尺度", "y_scale", ("linear", "log"))
        self.check(axis, 6, "绘图时自动缩放 X/Y", "auto_scale")
        ttk.Button(axis, text="自动坐标范围", command=self.auto_limits).grid(row=7, column=0, columnspan=2, sticky="ew", pady=8)
        process = process_panel.inner
        self.cal_box = self.entry(process, 0, "校准文件", "cal_file", ("",))
        self.entry(process, 1, "校准 X 列", "cal_x_column")
        self.entry(process, 2, "校准 Y 列", "cal_y_column")
        self.check(process, 3, "扣除所选校准曲线", "subtract_calibration")
        self.entry(process, 4, "Y 补偿 (dB)", "y_offset")
        self.entry(process, 5, "X 缩放", "x_factor")
        self.entry(process, 6, "Y 缩放", "y_factor")
        self.check(process, 7, "启用 smooth", "smooth")
        self.smooth_input = self.entry(process, 8, "smooth 点数", "smooth_points")
        ttk.Separator(process).grid(row=9, column=0, columnspan=2, sticky="ew", pady=8)
        self.curve_a = tk.StringVar()
        self.curve_b = tk.StringVar()
        self.save_curve = tk.StringVar()
        self.curve_boxes = []
        for row, text, variable in ((10, "曲线 A", self.curve_a), (11, "曲线 B", self.curve_b), (13, "保存曲线", self.save_curve)):
            ttk.Label(process, text=text).grid(row=row, column=0, sticky="w", pady=4)
            box = ttk.Combobox(process, textvariable=variable, state="readonly", width=15)
            box.grid(row=row, column=1, sticky="ew", pady=4)
            self.curve_boxes.append(box)
        ttk.Button(process, text="相减并作图", command=self.subtract_curves).grid(row=12, column=0, columnspan=2, sticky="ew", pady=6)
        self.output_name = tk.StringVar()
        ttk.Label(process, text="文件名").grid(row=14, column=0, sticky="w")
        ttk.Entry(process, textvariable=self.output_name, width=15).grid(row=14, column=1, sticky="ew", pady=4)
        ttk.Button(process, text="保存处理后曲线数据（CSV）", command=self.save_csv).grid(row=15, column=0, columnspan=2, sticky="ew", pady=8)
        style = ttk.LabelFrame(right, text="图形属性", padding=(8, 4))
        style.pack(fill="x", pady=(0, 6))
        self.entry(style, 0, "图标题", "title", span=3)
        self.entry(style, 1, "X 轴标题", "xlabel")
        self.entry(style, 1, "Y 轴标题", "ylabel", column=2)
        self.entry(style, 2, "刻度字号", "font_size")
        self.entry(style, 2, "图例字号", "legend_font", column=2)
        self.entry(style, 3, "图例列数", "legend_columns")
        self.entry(style, 3, "图例位置", "legend_location", tuple(LEGEND_LOCATIONS), column=2)
        self.entry(style, 4, "曲线线宽", "line_width")
        self.entry(style, 4, "渲染方式", "render_mode", ("抗锯齿", "快速"), column=2)
        checks = ttk.Frame(style)
        checks.grid(row=5, column=0, columnspan=4, sticky="ew")
        for column, (text, key) in enumerate((("轴标题粗体", "bold"), ("显示图例", "legend"), ("显示网格", "grid"))):
            self.check(checks, 0, text, key, column, 1)
        self.check(style, 6, "加入上下限 yline", "yline")
        self.check(style, 7, "使用默认图例名称", "default_legend")
        ttk.Button(style, text="编辑图例…", command=self.edit_legends).grid(row=7, column=2, columnspan=2, sticky="ew", pady=5)
        plot_frame = ttk.Frame(right)
        plot_frame.pack(fill="both", expand=True)
        self.figure = Figure(figsize=(6, 4), dpi=100, layout="constrained")
        self.axes = self.figure.add_subplot(111)
        self.canvas = FigureCanvasTkAgg(self.figure, master=plot_frame)
        self.canvas.get_tk_widget().pack(fill="both", expand=True)
        toolbar_frame = ttk.Frame(right)
        toolbar_frame.pack(fill="x")
        self.toolbar = NavigationToolbar2Tk(self.canvas, toolbar_frame, pack_toolbar=False)
        self.toolbar.pack(fill="x")
        self.axes.callbacks.connect("xlim_changed", self.axes_changed)
        self.axes.callbacks.connect("ylim_changed", self.axes_changed)
        self.status_label = ttk.Label(outer, text="请选择文件后绘图", anchor="w", wraplength=1200)
        self.status_label.pack(fill="x", pady=(6, 0))

    def values(self):
        values = {}
        for key, default in DEFAULTS.items():
            value = self.vars[key].get()
            if isinstance(default, bool):
                values[key] = bool(value)
            elif isinstance(default, int):
                number = float(value)
                if not np.isfinite(number) or number < 1 or number != int(number):
                    raise ValueError(f"{key} 必须为正整数")
                values[key] = int(number)
            elif isinstance(default, float):
                values[key] = float(value)
                if not np.isfinite(values[key]):
                    raise ValueError(f"{key} 必须为有限数值")
            else:
                values[key] = value
        if not 0.1 <= values["line_width"] <= 20:
            raise ValueError("曲线线宽须在 0.1–20 之间")
        if values["legend_columns"] > 20:
            raise ValueError("图例列数最大为 20")
        for dimension in ("x", "y"):
            low, high = values[dimension + "min"], values[dimension + "max"]
            for limit in (low, high):
                if limit.strip():
                    number = float(limit)
                    if not np.isfinite(number) or (values[dimension + "_scale"] == "log" and number <= 0):
                        raise ValueError("对数轴范围必须为正数，线性轴范围必须为有限数值")
            if low.strip() and high.strip() and float(low) >= float(high):
                raise ValueError(f"{dimension.upper()} 最小值必须小于最大值")
        return values

    def changed(self, key):
        if self.updating or self.closed:
            return
        if key in ("xmin", "xmax", "ymin", "ymax"):
            self.updating = True
            self.vars["auto_scale"].set(False)
            self.updating = False
        if key == "auto_scale" and self.vars[key].get():
            self.auto_limits()
        elif key in DATA_KEYS:
            self.request_data()
        else:
            self.after("render", 150, lambda: self.render(reset_view=key in AXIS_KEYS))
        self.after("settings", 350, self.persist)

    def selected_files(self):
        return [self.folder / self.file_list.get(index) for index in self.file_list.curselection()]

    def refresh_files(self):
        selected = {path.name for path in self.selected_files()}
        try:
            names = sorted(path.name for path in self.folder.iterdir() if path.is_file() and path.suffix.lower() in (".txt", ".csv", ".dat"))
        except OSError as error:
            self.status(str(error), True)
            return
        self.file_list.delete(0, "end")
        for index, name in enumerate(names):
            self.file_list.insert("end", name)
            if name in selected:
                self.file_list.selection_set(index)
        self.cal_box.configure(values=names or [""])
        self.updating = True
        if self.vars["cal_file"].get() not in names:
            self.vars["cal_file"].set("PC+polarizer.txt" if "PC+polarizer.txt" in names else (names[0] if names else ""))
        self.updating = False
        self.request_data()

    def select_all(self):
        self.file_list.selection_set(0, "end")
        self.request_data()

    def clear_selection(self):
        self.file_list.selection_clear(0, "end")
        self.request_data()

    def choose_folder(self):
        folder = filedialog.askdirectory(parent=self.root, initialdir=str(self.folder), title="选择数据目录")
        if folder:
            self.folder = Path(folder)
            self.vars["directory"].set(folder)
            self.recipes.clear()
            self.refresh_files()
            self.persist()

    def request_data(self, reset_view=False):
        self.generation += 1
        self.after("reload", 180, lambda: self.submit_data(reset_view))

    def submit_data(self, reset_view=False):
        try:
            values = self.values()
        except (ValueError, tk.TclError) as error:
            self.status(str(error), True)
            return
        files = self.selected_files()
        if not files:
            self.pending_load = None
            self.curves.clear()
            self.recipes.clear()
            self.render()
            self.status("未选择作图文件")
            return
        self.smooth_input.configure(state="normal" if values["smooth"] else "disabled")
        snapshot = (self.generation, files, values, dict(self.settings.legends), list(self.recipes), reset_view)
        if self.future:
            self.pending_load = snapshot
        else:
            self.start_load(snapshot)

    def start_load(self, snapshot):
        self.future = self.executor.submit(self.load_curves, snapshot)
        self.status("正在读取并处理曲线…")
        self.after("result", 40, self.collect_data)

    def cached_data(self, path):
        for _attempt in range(2):
            stat = path.stat()
            stamp = (stat.st_mtime_ns, stat.st_size)
            cached = self.data_cache.get(path)
            if cached and cached[0] == stamp:
                return cached[1]
            data = read_numeric(path)
            current = path.stat()
            if stamp == (current.st_mtime_ns, current.st_size):
                if len(self.data_cache) >= 32:
                    self.data_cache.clear()
                self.data_cache[path] = (stamp, data)
                return data
        raise ValueError(f"{path.name} 正在写入，请等待完整文件后刷新")

    def load_curves(self, snapshot):
        generation, files, values, labels, recipes, reset_view = snapshot
        calibration = self.cached_data(files[0].parent / values["cal_file"]) if values["subtract_calibration"] else None
        curves = []
        for path in files:
            x, y = process_data(self.cached_data(path), values, calibration)
            key = str(path.resolve())
            name = path.stem if values["default_legend"] else (labels.get(key) or path.stem)
            curves.append(Curve(key, name, x, y, path))
        by_key = {curve.key: curve for curve in curves}
        for a_key, b_key, key in recipes:
            if a_key in by_key and b_key in by_key:
                curve = difference(by_key[a_key], by_key[b_key], values, key)
                curves.append(curve)
                by_key[key] = curve
        return generation, curves, reset_view

    def collect_data(self):
        if not self.future.done():
            self.after("result", 40, self.collect_data)
            return
        future, self.future = self.future, None
        try:
            generation, curves, reset = future.result()
            if generation == self.generation:
                self.curves = curves
                self.render(reset)
                self.status(f"已绘制 {len(curves)} 条曲线")
        except Exception as error:
            self.status(f"读取失败，保留上一帧：{error}", True)
        if self.pending_load:
            snapshot, self.pending_load = self.pending_load, None
            self.start_load(snapshot)

    def curve_choices(self):
        labels = [f"{index + 1}: {curve.name}" for index, curve in enumerate(self.curves)]
        for box in self.curve_boxes:
            previous = box.get()
            box.configure(values=labels)
            if previous not in labels:
                box.set(labels[0] if labels else "")
        if len(labels) > 1 and self.curve_a.get() == self.curve_b.get():
            self.curve_b.set(labels[1])

    def selected_curve(self, variable):
        text = variable.get()
        try:
            return self.curves[int(text.split(":", 1)[0]) - 1]
        except (ValueError, IndexError):
            raise ValueError("请选择当前已绘制的曲线") from None

    def subtract_curves(self):
        try:
            a, b = self.selected_curve(self.curve_a), self.selected_curve(self.curve_b)
            if a.key == b.key:
                raise ValueError("曲线 A 和 B 不能为同一条曲线")
            key = f"difference:{len(self.recipes) + 1}"
            curve = difference(a, b, self.values(), key)
            self.recipes.append((a.key, b.key, key))
            self.curves.append(curve)
            self.render()
            self.status(f"曲线相减完成：{curve.name}")
        except ValueError as error:
            self.status(str(error), True)

    def render(self, reset_view=False):
        if self.closed:
            return
        try:
            values = self.values()
            self.rendering = True
            self.clear_ylines()
            keys = {curve.key for curve in self.curves}
            for key in list(self.lines):
                if key not in keys:
                    self.lines.pop(key).remove()
            for curve in self.curves:
                line = self.lines.get(curve.key)
                if line is None:
                    line, = self.axes.plot(curve.x, curve.y, label=curve.name, linestyle="--" if curve.source is None else "-")
                    self.lines[curve.key] = line
                else:
                    line.set_data(curve.x, curve.y)
                    line.set_label(curve.name)
                line.set_linewidth(values["line_width"])
                line.set_antialiased(values["render_mode"] == "抗锯齿")
            self.axes.set_xscale(values["x_scale"])
            self.axes.set_yscale(values["y_scale"])
            if values["auto_scale"] or reset_view or not self.preserve_view:
                self.axes.relim()
                self.axes.autoscale(enable=True, axis="both")
                self.axes.margins(x=0)
                self.axes.autoscale_view()
                for dimension in ("x", "y"):
                    getter = self.axes.get_xlim if dimension == "x" else self.axes.get_ylim
                    setter = self.axes.set_xlim if dimension == "x" else self.axes.set_ylim
                    low, high = getter()
                    minimum, maximum = values[dimension + "min"], values[dimension + "max"]
                    if minimum.strip():
                        low = float(minimum)
                    if maximum.strip():
                        high = float(maximum)
                    if low >= high:
                        raise ValueError(f"{dimension.upper()} 轴范围无效")
                    setter(low, high)
            else:
                self.axes.set_xlim(self.preserve_view[0])
                self.axes.set_ylim(self.preserve_view[1])
            self.preserve_view = (self.axes.get_xlim(), self.axes.get_ylim())
            weight = "bold" if values["bold"] else "normal"
            self.axes.set_title(title_math(values["title"]), fontsize=values["font_size"])
            self.axes.set_xlabel(values["xlabel"], fontsize=values["font_size"], fontweight=weight)
            self.axes.set_ylabel(values["ylabel"], fontsize=values["font_size"], fontweight=weight)
            self.axes.tick_params(labelsize=values["font_size"])
            self.axes.grid(values["grid"], alpha=0.35)
            legend = self.axes.get_legend()
            if legend:
                legend.remove()
            if values["legend"] and self.curves:
                handles = [self.lines[curve.key] for curve in self.curves]
                self.axes.legend(handles=handles, labels=[curve.name for curve in self.curves], loc=LEGEND_LOCATIONS[values["legend_location"]], ncols=values["legend_columns"], fontsize=values["legend_font"])
            self.update_ylines()
            self.curve_choices()
            self.canvas.draw_idle()
        except (ValueError, tk.TclError) as error:
            self.status(f"绘图设置无效：{error}", True)
        finally:
            self.rendering = False

    def clear_ylines(self):
        for artist in self.yline_artists:
            artist.remove()
        self.yline_artists.clear()

    def update_ylines(self):
        self.clear_ylines()
        if not self.vars["yline"].get():
            return
        result = visible_extrema(self.curves, self.axes.get_xlim(), self.axes.get_ylim())
        if result is None:
            return
        ymax, ymin = result
        for value, color, align in ((ymax, "#7d2e90", "top"), (ymin, "#d7541c", "bottom")):
            line = self.axes.axhline(value, color=color, linestyle="--", linewidth=max(1, float(self.vars["line_width"].get())), label="_nolegend_")
            label = self.axes.annotate(f"{value:.6g}", (0.015, value), xycoords=self.axes.get_yaxis_transform(), xytext=(0, -3 if align == "top" else 3), textcoords="offset points", color=color, va=align, fontsize=11, annotation_clip=True, bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.8, "pad": 1})
            self.yline_artists.extend((line, label))

    def axes_changed(self, _axes):
        if self.closed or self.rendering:
            return
        self.preserve_view = (self.axes.get_xlim(), self.axes.get_ylim())
        # 工具栏缩放/平移后把实际视图同步到范围控件，后续重绘继续使用该范围。
        self.updating = True
        self.vars["auto_scale"].set(False)
        for key, value in zip(("xmin", "xmax", "ymin", "ymax"), (*self.preserve_view[0], *self.preserve_view[1])):
            self.vars[key].set(f"{value:.12g}")
        self.updating = False
        self.after("ylines", 60, self.refresh_ylines)
        self.after("settings", 350, self.persist)

    def refresh_ylines(self):
        self.rendering = True
        try:
            self.update_ylines()
            self.canvas.draw_idle()
        finally:
            self.rendering = False

    def auto_limits(self):
        self.updating = True
        self.vars["auto_scale"].set(True)
        for key in ("xmin", "xmax", "ymin", "ymax"):
            self.vars[key].set("")
        self.updating = False
        self.render(reset_view=True)
        self.after("settings", 350, self.persist)

    def save_csv(self):
        try:
            curve = self.selected_curve(self.save_curve)
            name = self.output_name.get().strip() or curve.name + "_processed"
            path, count = write_visible_csv(self.folder, name, curve, self.axes.get_xlim(), self.axes.get_ylim())
            self.status(f"保存成功：图窗可见数据 {count} 点；{path}")
        except (ValueError, OSError) as error:
            self.status(f"保存失败：{error}", True)

    def preview(self, event):
        index = self.file_list.nearest(event.y)
        if index < 0 or index >= self.file_list.size():
            return "break"
        path = self.folder / self.file_list.get(index)
        try:
            data = read_numeric(path, max_rows=5000)
        except (ValueError, OSError) as error:
            self.status(f"预览失败：{error}", True)
            return "break"
        window = tk.Toplevel(self.root)
        window.title("数据预览 — " + path.name)
        window.geometry("900x550")
        window.rowconfigure(1, weight=1)
        window.columnconfigure(0, weight=1)
        ttk.Label(window, text=f"{path.name} · 预览 {len(data)} 行").grid(row=0, column=0, sticky="w", padx=10, pady=8)
        headings = ["行号"] + [f"列 {index + 1}" for index in range(data.shape[1])]
        table = ttk.Treeview(window, columns=headings, show="headings")
        for heading in headings:
            table.heading(heading, text=heading)
            table.column(heading, width=130, minwidth=70, stretch=True)
        for index, row in enumerate(data):
            table.insert("", "end", values=[index + 1] + [f"{value:.12g}" for value in row])
        table.grid(row=1, column=0, sticky="nsew", padx=(10, 0))
        ttk.Scrollbar(window, orient="vertical", command=table.yview).grid(row=1, column=1, sticky="ns")
        vertical = window.grid_slaves(row=1, column=1)[0]
        table.configure(yscrollcommand=vertical.set)
        horizontal = ttk.Scrollbar(window, orient="horizontal", command=table.xview)
        horizontal.grid(row=2, column=0, sticky="ew", padx=10)
        table.configure(xscrollcommand=horizontal.set)
        return "break"

    def edit_legends(self):
        window = tk.Toplevel(self.root)
        window.title("编辑图例")
        window.geometry("620x450")
        panel = ScrollPanel(window, "图例名称")
        panel.pack(fill="both", expand=True, padx=8, pady=8)
        for index, path in enumerate(self.selected_files()):
            key = str(path.resolve())
            ttk.Label(panel.inner, text=path.name, wraplength=230).grid(row=index, column=0, sticky="w", pady=5)
            label_var = tk.StringVar(value=self.settings.legends.get(key, path.stem))
            ttk.Entry(panel.inner, textvariable=label_var).grid(row=index, column=1, sticky="ew", padx=8, pady=5)
            def update(*_args, k=key, variable=label_var):
                self.settings.legends[k] = variable.get()
                self.vars["default_legend"].set(False)
                self.request_data()
                self.after("settings", 350, self.persist)
            label_var.trace_add("write", update)
        panel.inner.columnconfigure(1, weight=1)

    def watch_files(self):
        if self.vars["watch_files"].get():
            files = self.selected_files()
            if self.vars["subtract_calibration"].get():
                files.append(self.folder / self.vars["cal_file"].get())
            try:
                stamps = {str(path): (path.stat().st_mtime_ns, path.stat().st_size) for path in files}
                if self.file_stamps and stamps != self.file_stamps:
                    self.request_data()
                self.file_stamps = stamps
            except OSError as error:
                self.status(f"监视文件失败：{error}", True)
        else:
            self.file_stamps.clear()
        self.after("watch", 1000, self.watch_files)

    def persist(self):
        try:
            self.settings.values = self.values()
            self.settings.values["geometry"] = self.root.geometry()
            self.settings.save(self.config)
        except (ValueError, tk.TclError, OSError) as error:
            self.status(f"配置未保存：{error}", True)

    def resized(self, event):
        if event.widget == self.root and not self.closed:
            self.after("settings", 350, self.persist)

    def close(self):
        if self.closed:
            return
        self.persist()
        self.closed = True
        for job in self.jobs.values():
            self.root.after_cancel(job)
        self.jobs.clear()
        self.executor.shutdown(wait=False, cancel_futures=True)
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser(description="PlotGUI 数据绘图GUI")
    parser.add_argument("directory", nargs="?", type=Path)
    parser.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("--gui-smoke-test", action="store_true")
    args = parser.parse_args()
    root = tk.Tk()
    if args.gui_smoke_test:
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            root.withdraw()
            app = PlotGUI(root, Path(temporary), Path(temporary) / "settings.json")
            root.update()
            app.close()
            print("GUI_OPEN_CLOSE_OK")
        return
    PlotGUI(root, args.directory)
    root.mainloop()


if __name__ == "__main__":
    main()
