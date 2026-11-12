"""Package the static web app as one portable offline HTML file."""
from pathlib import Path

root=Path(__file__).resolve().parent
page=(root/'index.html').read_text(encoding='utf-8')
page=page.replace('<link rel="stylesheet" href="style.css">','<style>\n'+(root/'style.css').read_text(encoding='utf-8')+'\n</style>')
for name in ['vendor/plotly.min.js','plot_core.js','clipboard.js','app.js']:
    script=(root/name).read_text(encoding='utf-8').replace('</script','<\\/script')
    page=page.replace('<script src="'+name+'"></script>','<script>\n'+script+'\n</script>')
target=root/'PlotGUI-Web.html'
target.write_text(page,encoding='utf-8')
print(target)
