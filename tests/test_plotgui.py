"""验证校准、平滑、可见范围导出以及 GUI 更新后的 yline。"""

import csv
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from plot_core import (
    Curve, DEFAULTS, Settings, columns, difference, moving_mean,
    process_data, read_numeric, visible_extrema, write_visible_csv,
)


class DataTests(unittest.TestCase):
    def test_parser_preserves_columns_and_handles_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "中文.csv"
            path.write_text("# settings\nX,Unused,Y\n1,,2D0\n2,9,-3\n3,0,NaN\n", encoding="utf-8-sig")
            data = read_numeric(path)
            x, y = columns(data, 1, 3)
            np.testing.assert_array_equal(x, [1, 2])
            np.testing.assert_array_equal(y, [2, -3])
            self.assertTrue(np.isnan(data[0, 1]))

    def test_matlab_even_and_odd_smooth_endpoints(self):
        np.testing.assert_allclose(moving_mean(np.array([1., 3., 8., 0.]), 2), [1, 2, 5.5, 4])
        np.testing.assert_allclose(moving_mean(np.array([1., 3., 8., 0.]), 3), [2, 4, 11 / 3, 4])

    def test_scale_then_calibration_then_compensation(self):
        values = dict(DEFAULTS, y_column=2, cal_y_column=2, x_factor=2., y_factor=3., y_offset=1., subtract_calibration=True)
        x, y = process_data(np.array([[0, 2], [1, 4], [2, 8], [3, 10]]), values, np.array([[0, 1], [2, 3]]))
        np.testing.assert_allclose(x, [0, 2, 4])
        np.testing.assert_allclose(y, [4, 7, 16])

    def test_difference_uses_overlap_and_sorted_unique_x(self):
        a = Curve("a", "A", np.array([3, 1, 2, 2]), np.array([9, 3, 6, 100]))
        b = Curve("b", "B", np.array([1, 3]), np.array([1, 3]))
        result = difference(a, b, DEFAULTS, "a-b")
        np.testing.assert_allclose(result.x, [1, 2, 3])
        np.testing.assert_allclose(result.y, [2, 4, 6])

    def test_yline_and_export_use_current_visible_processed_values(self):
        curve = Curve("a", "A", np.array([0, 1, 2, 3, 4, 5]), np.array([-8, -4.32, -4.5, -4.6, -3, -4.4]))
        self.assertEqual(visible_extrema([curve], (1, 4), (-5, -4)), (-4.32, -4.6))
        with tempfile.TemporaryDirectory() as directory:
            first, count = write_visible_csv(Path(directory), "曲线", curve, (1, 4), (-5, -4))
            second, _ = write_visible_csv(Path(directory), "曲线", curve, (1, 4), (-5, -4))
            self.assertNotEqual(first, second)
            self.assertEqual(count, 3)
            self.assertEqual(first.read_bytes()[:3], b"\xef\xbb\xbf")
            with first.open(encoding="utf-8-sig", newline="") as stream:
                rows = list(csv.reader(stream))
            self.assertEqual(rows[0], ["X", "Y"])
            np.testing.assert_allclose(np.array(rows[1:], dtype=float), [[1, -4.32], [2, -4.5], [3, -4.6]])
            with self.assertRaises(ValueError):
                write_visible_csv(Path(directory), "empty", curve, (100, 200), (-5, -4))

    def test_settings_roundtrip_and_invalid_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            settings = Settings()
            settings.values.update(smooth_points=27, geometry="1280x800", font_size=22)
            settings.legends["curve.txt"] = "校准曲线"
            settings.save(path)
            restored = Settings.load(path)
            self.assertEqual(restored.values["smooth_points"], 27)
            self.assertEqual(restored.legends["curve.txt"], "校准曲线")
            path.write_text('{"values":{"smooth_points":-7,"y_scale":"broken"}}')
            restored = Settings.load(path)
            self.assertEqual(restored.values["smooth_points"], 1)
            self.assertEqual(restored.values["y_scale"], "linear")


class GUITests(unittest.TestCase):
    def test_file_read_and_parameter_callbacks_refresh_ylines(self):
        import time
        import tkinter as tk
        from plot_gui import PlotGUI

        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "sample.txt").write_text("0 0 -4.8\n1 0 -4.32\n2 0 -4.5\n3 0 -4.6\n4 0 -4.2\n")
            root = tk.Tk()
            root.withdraw()
            app = PlotGUI(root, folder, folder / "settings.json")
            try:
                app.updating = True
                for key, value in {"yline": True, "auto_scale": False, "xmin": "1", "xmax": "3", "ymin": "-5", "ymax": "-4"}.items():
                    app.vars[key].set(value)
                app.updating = False
                app.file_list.selection_set(0)
                app.request_data(reset_view=True)

                def wait_for_frame():
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        root.update()
                        if app.curves and not app.future and "reload" not in app.jobs:
                            return
                        time.sleep(0.01)
                    self.fail("数据重绘未完成")

                wait_for_frame()
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], [-4.32, -4.6])
                app.vars["y_offset"].set("0.1")
                wait_for_frame()
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], [-4.22, -4.5])
                app.vars["smooth"].set(True)
                app.vars["smooth_points"].set("3")
                wait_for_frame()
                expected = visible_extrema(app.curves, app.axes.get_xlim(), app.axes.get_ylim())
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], expected)
                app.save_csv()
                saved = list(folder.glob("*.csv"))
                self.assertEqual(len(saved), 1)
                exported = read_numeric(saved[0])
                self.assertEqual(len(exported), 3)
                self.assertTrue((exported[:, 0] >= 1).all() and (exported[:, 0] <= 3).all())
            finally:
                app.close()

    def test_yline_updates_after_data_smooth_and_view_changes(self):
        import tkinter as tk
        from plot_gui import PlotGUI

        with tempfile.TemporaryDirectory() as directory:
            root = tk.Tk()
            root.withdraw()
            app = PlotGUI(root, Path(directory), Path(directory) / "settings.json")
            try:
                app.updating = True
                for key, value in {"yline": True, "auto_scale": False, "xmin": "1", "xmax": "4", "ymin": "-5", "ymax": "-4"}.items():
                    app.vars[key].set(value)
                app.updating = False
                raw = np.array([-8., -4.32, -4.5, -4.6, -3.])
                app.curves = [Curve("a", "A", np.arange(5), raw.copy())]
                app.render(reset_view=True)
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], [-4.32, -4.6])
                app.curves[0].y += 0.1
                app.render()
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], [-4.22, -4.5])
                app.curves[0].y = moving_mean(raw, 3)
                app.render()
                expected = visible_extrema(app.curves, app.axes.get_xlim(), app.axes.get_ylim())
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], expected)
                app.axes.set_xlim(2, 3)
                app.refresh_ylines()
                expected = visible_extrema(app.curves, app.axes.get_xlim(), app.axes.get_ylim())
                np.testing.assert_allclose([line.get_ydata()[0] for line in app.yline_artists[::2]], expected)
                app.canvas.draw()
                self.assertEqual(len(app.lines), 1)
            finally:
                app.close()
            self.assertFalse(app.jobs)


if __name__ == "__main__":
    unittest.main()
