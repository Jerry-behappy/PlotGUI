/* Numerical port of python/plot_core.py. No browser or plotting dependency. */
(function(root){
'use strict';
const DEFAULTS={x_column:1,y_column:3,cal_x_column:1,cal_y_column:3,cal_file:'',subtract_calibration:false,smooth:false,smooth_points:5,x_factor:1,y_factor:1,y_offset:0,xmin:'',xmax:'',ymin:'',ymax:'',x_scale:'linear',y_scale:'linear',auto_scale:true,title:'',xlabel:'Wavelength (nm)',ylabel:'Loss (dB)',font:'Microsoft YaHei',font_size:24,label_size:24,legend_font:24,analysis_font:17,legend_columns:1,legend_location:'northeast',bold:true,legend:true,grid:true,default_legend:true,yline:false,line_width:3,render_mode:'抗锯齿',show_max:true,show_analysis:true,connect_gaps:true,hide_sentinel:false,watch_files:false};
function splitCSV(row){const out=[];let value='',quoted=false;for(let i=0;i<row.length;i++){const c=row[i];if(c==='"'){if(quoted&&row[i+1]==='"'){value+='"';i++}else quoted=!quoted}else if(c===','&&!quoted){out.push(value);value=''}else value+=c}out.push(value);return out}
function number(token){token=token.trim().replace(/[dD]/g,'e');if(!token||!/^[-+]?(?:(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|inf(?:inity)?|nan)$/i.test(token))return NaN;return Number(token)}
function readNumeric(text,maxRows=Infinity){
  const rows=[];let width=0,headers=[];
  for(const raw of text.replace(/^\uFEFF/,'').split(/\r?\n/)){
    const line=raw.trim();if(!line||/^(#|%|\/\/)/.test(line))continue;
    const tokens=line.includes('\t')?line.split('\t'):line.includes(',')?splitCSV(line):line.includes(';')?line.split(';'):line.split(/\s+/);
    const row=tokens.map(number);
    if(row.some(Number.isFinite)){rows.push(row);width=Math.max(width,row.length);if(rows.length>=maxRows)break}
    else if(!rows.length&&tokens.length>1)headers=tokens.map(s=>s.trim());
  }
  if(!rows.length)throw Error('没有可用数值数据');
  for(const row of rows)while(row.length<width)row.push(NaN);
  return {rows,width,headers:headers.length===width?headers:Array.from({length:width},(_,i)=>'Column '+(i+1))};
}
function columns(data,xColumn,yColumn){
  if(!Number.isInteger(xColumn)||!Number.isInteger(yColumn)||Math.min(xColumn,yColumn)<1||Math.max(xColumn,yColumn)>data.width)throw Error('所选 X/Y 列超出文件的 '+data.width+' 列');
  const x=[],y=[];for(const row of data.rows)if(Number.isFinite(row[xColumn-1])&&Number.isFinite(row[yColumn-1])){x.push(row[xColumn-1]);y.push(row[yColumn-1])}
  if(!x.length)throw Error('所选 X/Y 列没有有效数值');return {x,y};
}
function movingMean(y,window){
  window=Math.min(y.length,Math.max(1,Math.trunc(window)));if(window<=1)return y.slice();
  const total=[0];for(const value of y)total.push(total.at(-1)+value);
  return y.map((_,i)=>{const left=Math.max(0,i-Math.floor(window/2)),right=Math.min(y.length,i+Math.floor((window-1)/2)+1);return (total[right]-total[left])/(right-left)});
}
function sortedUnique(x,y){
  const order=x.map((_,i)=>i).sort((a,b)=>x[a]-x[b]||a-b),sx=[],sy=[];
  for(const i of order)if(!sx.length||x[i]!==sx.at(-1)){sx.push(x[i]);sy.push(y[i])}return {x:sx,y:sy};
}
function interpolate(x,y,at){
  if(at<x[0]||at>x.at(-1))return NaN;
  let lo=0,hi=x.length-1;while(lo+1<hi){const m=Math.floor((lo+hi)/2);if(x[m]<=at)lo=m;else hi=m}
  if(at===x[lo])return y[lo];if(at===x[hi])return y[hi];return y[lo]+(y[hi]-y[lo])*(at-x[lo])/(x[hi]-x[lo]);
}
function processData(data,values,calibration=null){
  let {x,y}=columns(data,Number(values.x_column),Number(values.y_column));x=x.map(v=>v*values.x_factor);y=y.map(v=>v*values.y_factor);
  if(values.subtract_calibration){
    if(!calibration)throw Error('请选择可用的校准曲线文件');
    const c=columns(calibration,Number(values.cal_x_column),Number(values.cal_y_column));
    const sorted=sortedUnique(c.x.map(v=>v*values.x_factor),c.y.map(v=>v*values.y_factor));
    if(sorted.x.length<2)throw Error('校准曲线至少需要两个不同的 X 点');
    const nx=[],ny=[];for(let i=0;i<x.length;i++){const cy=interpolate(sorted.x,sorted.y,x[i]);if(Number.isFinite(cy)){nx.push(x[i]);ny.push(y[i]-cy)}}x=nx;y=ny;
    if(!x.length)throw Error('曲线与校准文件没有重叠的 X 范围');
  }
  y=y.map(v=>v+Number(values.y_offset));if(values.smooth)y=movingMean(y,values.smooth_points);return {x,y};
}
function combine(a,b,values,halfSum=false){
  const sa=sortedUnique(a.x,a.y),sb=sortedUnique(b.x,b.y);if(sa.x.length<2||sb.x.length<2)throw Error('每条曲线至少需要两个不同的 X 点');
  const x=[],y=[];for(let i=0;i<sa.x.length;i++){const atB=interpolate(sb.x,sb.y,sa.x[i]);if(Number.isFinite(atB)){x.push(sa.x[i]);y.push(halfSum?(sa.y[i]+atB)/2:sa.y[i]-atB)}}
  if(!x.length)throw Error('曲线 A 和 B 没有重叠的 X 范围');
  return {x,y:values.smooth?movingMean(y,values.smooth_points):y};
}
function visibleData(curve,xlim,ylim){const x=[],y=[],xl=Math.min(...xlim),xh=Math.max(...xlim),yl=Math.min(...ylim),yh=Math.max(...ylim);for(let i=0;i<curve.x.length;i++)if(Number.isFinite(curve.x[i])&&Number.isFinite(curve.y[i])&&curve.x[i]>=xl&&curve.x[i]<=xh&&curve.y[i]>=yl&&curve.y[i]<=yh){x.push(curve.x[i]);y.push(curve.y[i])}return {x,y}}
function visibleExtrema(curves,xlim,ylim){let max=-Infinity,min=Infinity;for(const c of curves){const {y}=visibleData(c,xlim,ylim);for(const v of y){max=Math.max(max,v);min=Math.min(min,v)}}return max===-Infinity?null:{max,min}}
function maximum(curve){let j=-1;for(let i=0;i<curve.y.length;i++)if(Number.isFinite(curve.x[i])&&Number.isFinite(curve.y[i])&&(j<0||curve.y[i]>curve.y[j]))j=i;return j<0?null:{x:curve.x[j],y:curve.y[j]}}
function csv(curve){return 'X,Y\r\n'+curve.x.map((x,i)=>x+','+curve.y[i]).join('\r\n')}
function validate(v){
  for(const k of ['x_column','y_column','cal_x_column','cal_y_column','smooth_points','font_size','label_size','legend_font','analysis_font','legend_columns'])if(!Number.isInteger(v[k])||v[k]<1)throw Error(k+' 必须为正整数');
  for(const k of ['x_factor','y_factor','y_offset','line_width'])if(!Number.isFinite(v[k]))throw Error(k+' 必须为有限数值');
  if(v.line_width<.1||v.line_width>20)throw Error('曲线线宽须在 0.1–20 之间');if(v.legend_columns>20)throw Error('图例列数最大为 20');
  for(const axis of ['x','y']){if(!['linear','log'].includes(v[axis+'_scale']))throw Error('坐标尺度无效');for(const k of [axis+'min',axis+'max'])if(v[k]!==''&&(!Number.isFinite(Number(v[k]))||(v[axis+'_scale']==='log'&&Number(v[k])<=0)))throw Error('坐标范围必须有限，对数轴范围须大于 0');if(v[axis+'min']!==''&&v[axis+'max']!==''&&Number(v[axis+'min'])>=Number(v[axis+'max']))throw Error(axis.toUpperCase()+' 最小值必须小于最大值')}
  return v;
}
const api={DEFAULTS,readNumeric,columns,movingMean,sortedUnique,interpolate,processData,combine,visibleData,visibleExtrema,maximum,csv,validate};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.PlotCore=api;
})(typeof window==='undefined'?globalThis:window);
