"""Package the static web app as one portable offline HTML file."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def build_single_file(target: Path | None = None) -> Path:
    """Embed every runtime asset and its license; importing this module writes nothing."""
    page = (ROOT / 'index.html').read_text(encoding='utf-8')
    page = page.replace('<link rel="stylesheet" href="style.css">',
                        '<style>\n' + (ROOT / 'style.css').read_text(encoding='utf-8') + '\n</style>')
    for name in ['vendor/plotly.min.js', 'plot_core.js', 'clipboard.js', 'app.js']:
        script = (ROOT / name).read_text(encoding='utf-8').replace('</script', '<\\/script')
        page = page.replace('<script src="' + name + '"></script>', '<script>\n' + script + '\n</script>')
    notices = '\n\n'.join((ROOT / 'vendor' / name).read_text(encoding='utf-8')
                            for name in ['LICENSE-plotly.txt', 'plotly.min.js.LICENSE.txt'])
    page = page.replace('</head>', '<!-- Third-party licenses\n' + notices.replace('-->', '-- >') + '\n-->\n</head>', 1)
    target = target or ROOT / 'PlotGUI-Web.html'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(page, encoding='utf-8')
    return target


if __name__ == '__main__':
    print(build_single_file())
