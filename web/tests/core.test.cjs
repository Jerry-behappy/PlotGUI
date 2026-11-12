const test=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const path=require('node:path');
const C=require('../plot_core.js');
function close(actual,expected,tolerance=1e-10){assert.equal(actual.length,expected.length);actual.forEach((n,i)=>assert.ok(Math.abs(n-expected[i])<tolerance,`${i}: ${n} != ${expected[i]}`))}
test('CSV/TXT/DAT preserve empty columns, comments and Fortran exponents',()=>{
 const d=C.readNumeric('# settings\nX,Unused,Y\n1,,2D0\n2,9,-3\n3,0,NaN\n');
 assert.equal(d.width,3);assert(Number.isNaN(d.rows[0][1]));assert.deepEqual(C.columns(d,1,3),{x:[1,2],y:[2,-3]});
 assert.deepEqual(C.columns(C.readNumeric('% header\n1;2\n2;4'),1,2),{x:[1,2],y:[2,4]});
 assert.deepEqual(C.columns(C.readNumeric('X\tY\n1\t2\n2\t4'),1,2),{x:[1,2],y:[2,4]});
 assert.throws(()=>C.readNumeric('header only'),/没有可用/);
});
test('MATLAB movmean even and odd edge windows',()=>{close(C.movingMean([1,3,8,0],2),[1,2,5.5,4]);close(C.movingMean([1,3,8,0],3),[2,4,11/3,4])});
test('scale -> calibration on overlap -> offset -> smooth',()=>{
 const v={...C.DEFAULTS,y_column:2,cal_y_column:2,x_factor:2,y_factor:3,y_offset:1,subtract_calibration:true};
 const result=C.processData(C.readNumeric('0 2\n1 4\n2 8\n3 10'),v,C.readNumeric('0 1\n2 3'));
 close(result.x,[0,2,4]);close(result.y,[4,7,16]);
 assert.throws(()=>C.processData(C.readNumeric('4 2\n5 3'),v,C.readNumeric('0 1\n1 2')),/没有重叠/);
});
test('subtraction sorts duplicate X stably and interpolates B only on overlap',()=>{
 const a={x:[3,1,2,2],y:[9,3,6,100]},b={x:[1,3],y:[1,3]};
 const result=C.combine(a,b,C.DEFAULTS);close(result.x,[1,2,3]);close(result.y,[2,4,6]);
 close(C.combine(a,{x:[1,3],y:[2,6]},C.DEFAULTS,true).y,[2.5,5,7.5]);
});
test('visible ylines and copied CSV use both X and Y limits',()=>{
 const c={x:[0,1,2,3,4,5],y:[-8,-4.32,-4.5,-4.6,-3,-4.4]};
 assert.deepEqual(C.visibleExtrema([c],[1,4],[-5,-4]),{max:-4.32,min:-4.6});
 assert.equal(C.csv(C.visibleData(c,[1,4],[-5,-4])),'X,Y\r\n1,-4.32\r\n2,-4.5\r\n3,-4.6');
 assert.equal(C.visibleExtrema([c],[100,200],[-5,-4]),null);
});
test('reject invalid processing and logarithmic ranges',()=>{
 assert.throws(()=>C.validate({...C.DEFAULTS,smooth_points:2.5}),/正整数/);
 assert.throws(()=>C.validate({...C.DEFAULTS,x_scale:'log',xmin:'-1'}),/对数轴/);
 assert.throws(()=>C.validate({...C.DEFAULTS,xmin:'3',xmax:'1'}),/最小值/);
 assert.throws(()=>C.columns(C.readNumeric('1 2\n2 3'),1,3),/超出/);
});
test('dropped folders traverse subdirectories and every entry batch',async()=>{
 const source=require('node:fs').readFileSync(path.resolve(__dirname,'../app.js'),'utf8');
 const start=source.indexOf('async function walkEntry('),end=source.indexOf('\nlet dragDepth',start);
 const context={};require('node:vm').createContext(context);require('node:vm').runInContext(source.slice(start,end),context);
 const file=name=>({isFile:true,name,file:resolve=>resolve({name})});
 const directory=(name,batches)=>({isDirectory:true,name,createReader:()=>{let index=0;return {readEntries:resolve=>resolve(batches[index++]||[])}}});
 const root=directory('Data',[[file('a.csv')],[directory('Nested',[[file('b.dat')],[]])],[]]);
 assert.deepEqual(Array.from(await context.walkEntry(root),item=>item.path),['Data/a.csv','Data/Nested/b.dat']);
});
test('JavaScript processing matches the owning Python implementation',()=>{
 const program=`
import sys,json
import numpy as np
sys.path.insert(0,sys.argv[1])
from plot_core import DEFAULTS,process_data,Curve,difference,visible_extrema,moving_mean
rng=np.random.default_rng(97)
data=np.column_stack([np.linspace(-1,6,157),rng.normal(size=157),rng.normal(size=157)])
cal=np.column_stack([np.linspace(0,5,43),np.zeros(43),rng.normal(size=43)])
cases=[]
for window in [2,5,12]:
 v=dict(DEFAULTS,x_factor=2.,y_factor=-3.,y_offset=.7,subtract_calibration=True,smooth=True,smooth_points=window)
 x,y=process_data(data,v,cal)
 cases.append(dict(data=data.tolist(),cal=cal.tolist(),values=v,x=x.tolist(),y=y.tolist()))
print(json.dumps(cases))
`;
 const result=spawnSync(process.env.PYTHON||'python',['-c',program,path.resolve(__dirname,'../../python')],{encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
 for(const fixture of JSON.parse(result.stdout)){
  const toData=rows=>({rows,width:rows[0].length});
  const actual=C.processData(toData(fixture.data),{...C.DEFAULTS,...fixture.values},toData(fixture.cal));close(actual.x,fixture.x);close(actual.y,fixture.y,2e-12);
 }
});
