// PNG is copied as an image; SVG and CSV are copied as editable text.
async function copyText(text,card,label='数据'){
  try{if(!navigator.clipboard?.writeText)throw Error('剪贴板不可用');await navigator.clipboard.writeText(text);card.el.querySelector('.status').textContent=label+'已复制'}
  catch(error){showCopyFallback(text,'text/plain',label);card.el.querySelector('.status').textContent='请在弹出的窗口中复制'+label}
}
function showCopyFallback(content,type,label){
  document.getElementById('copy-fallback')?.remove();
  const dialog=document.createElement('dialog');dialog.id='copy-fallback';dialog.style.cssText='border:1px solid #cbd7e0;border-radius:12px;padding:22px;max-width:min(880px,94vw);max-height:90vh';
  const title=document.createElement('h3');title.textContent='复制'+label;dialog.appendChild(title);
  const note=document.createElement('p');note.style.cssText='font-size:14px;color:#526d80';dialog.appendChild(note);
  let url;
  if(type==='image/png'){
    note.textContent='浏览器未允许直接写入剪贴板，请右键下方图片，选择“复制图片”。';
    url=URL.createObjectURL(content);const img=document.createElement('img');img.src=url;img.alt='待复制的图表';img.style.cssText='display:block;max-width:100%;max-height:62vh;object-fit:contain';dialog.appendChild(img);
  }else{
    note.textContent='点击“复制文本”，或选中文本后按 Ctrl+C。';
    const area=document.createElement('textarea');area.value=content;area.readOnly=true;area.style.cssText='width:min(760px,80vw);height:45vh;display:block;margin-bottom:14px';dialog.appendChild(area);
    const copy=document.createElement('button');copy.textContent='复制文本';copy.onclick=async()=>{area.focus();area.select();try{if(navigator.clipboard?.writeText)await navigator.clipboard.writeText(content);else if(!document.execCommand('copy'))throw Error();note.textContent='已复制'}catch(e){note.textContent='文本已选中，请按 Ctrl+C。'}};dialog.appendChild(copy);
  }
  const close=document.createElement('button');close.textContent='关闭';close.style.marginLeft='10px';close.onclick=()=>dialog.close();dialog.appendChild(close);
  dialog.addEventListener('close',()=>{if(url)URL.revokeObjectURL(url);dialog.remove()});document.body.appendChild(dialog);dialog.showModal();
}
async function copyFigure(card,format){
  card.el.querySelector('.status').textContent='正在准备复制…';
  if(format==='svg'){
    try{const blob=await exportFigure(card,'svg',true);await copyText(await blob.text(),card,'SVG 源码')}catch(e){card.el.querySelector('.status').textContent='复制失败：'+e.message}return;
  }
  const blobPromise=exportFigure(card,'png',true);
  try{
    if(!navigator.clipboard?.write||typeof ClipboardItem==='undefined')throw Error('浏览器不支持直接复制图片');
    // Start the clipboard request during the click gesture, before PNG rendering finishes.
    await navigator.clipboard.write([new ClipboardItem({'image/png':blobPromise})]);card.el.querySelector('.status').textContent='PNG 图片已复制';
  }catch(error){
    try{showCopyFallback(await blobPromise,'image/png','PNG 图片');card.el.querySelector('.status').textContent='请右键弹出的图片进行复制'}catch(e){card.el.querySelector('.status').textContent='复制失败：'+e.message}
  }
}
