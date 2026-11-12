"""Check that the Web release is actually standalone and contains only listed files."""
from html.parser import HTMLParser
from pathlib import Path
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from package_release import WEB_FILES, package_web


class RuntimeReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.external = []
        self.scripts = []
        self.active_script = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'script':
            if 'src' in attrs:
                self.external.append(attrs['src'])
            self.scripts.append('')
            self.active_script = True
        elif tag == 'link' and attrs.get('rel') == 'stylesheet':
            self.external.append(attrs['href'])

    def handle_endtag(self, tag):
        if tag == 'script':
            self.active_script = False

    def handle_data(self, data):
        if self.active_script:
            self.scripts[-1] += data


class ReleasePackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.output = Path(cls.temporary.name)
        package_web(ROOT, cls.output)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_single_html_has_no_runtime_file_dependencies(self):
        html = (self.output / 'PlotGUI-Web.html').read_text(encoding='utf-8')
        parsed = RuntimeReferences()
        parsed.feed(html)
        self.assertEqual(parsed.external, [])
        self.assertEqual(len(parsed.scripts), 4)
        self.assertTrue(all(script.strip() for script in parsed.scripts))
        license_text = (ROOT / 'web/vendor/LICENSE-plotly.txt').read_text(encoding='utf-8')
        self.assertTrue(license_text in html, 'Standalone HTML must preserve the Plotly license')
        self.assertTrue('Third-party licenses' in html)

    def test_zip_contains_standalone_and_every_editable_runtime_file(self):
        with ZipFile(self.output / 'PlotGUI-Web.zip') as archive:
            expected = {'PlotGUI-Web/' + name for name in WEB_FILES}
            expected.update({'PlotGUI-Web/PlotGUI-Web.html', 'PlotGUI-Web/开始使用.txt'})
            self.assertEqual(set(archive.namelist()), expected)
            self.assertTrue(archive.read('PlotGUI-Web/PlotGUI-Web.html') ==
                            (self.output / 'PlotGUI-Web.html').read_bytes(), 'Standalone HTML differs')
            for name in WEB_FILES:
                self.assertTrue(archive.read('PlotGUI-Web/' + name) ==
                                (ROOT / 'web' / name).read_bytes(), 'Packaged file differs: ' + name)


if __name__ == '__main__':
    unittest.main()
