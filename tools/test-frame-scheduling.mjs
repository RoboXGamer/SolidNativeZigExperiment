import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {Driver} from './driver.mjs';
process.chdir(fileURLToPath(new URL('../',import.meta.url)));
function run(command,args,env={}){const r=spawnSync(command,args,{encoding:'utf8',timeout:600000,env:{...process.env,...env}});if(r.status!==0)throw Error(r.stdout+r.stderr+r.error);}
let child,driver;
try{
  run(process.execPath,['tools/build-ui.mjs'],{DRAFT1_ENTRY:'/tests/fixtures/frame-probe.js'});
  run('zig',['build','-Ddriver=true']);
  const pipe=`solid-frames-${process.pid}`,token=randomBytes(24).toString('hex');
  child=spawn('zig-out/bin/windows.exe',[],{windowsHide:true,stdio:'ignore',env:{...process.env,SOLID_NATIVE_PIPE:pipe,SOLID_NATIVE_TOKEN:token,SOLID_NATIVE_CONTROLLED:'1',SOLID_NATIVE_DRIVER_HIDDEN:'1'}});
  driver=await Driver.connect({pipe,token});
  const tree=await driver.tree();const button=tree.find(n=>n.type==='button');
  const text=tree.find(n=>n.type==='text'&&n.text.startsWith('Edit examples/'));
  const before=await driver.command('metrics');
  for(let i=0;i<120;i++)await driver.command('pointer.move',{x:text.bounds.x+3+i%20,y:text.bounds.y+5});
  let now=await driver.command('metrics');assert.equal(now.revisions.paint,before.revisions.paint);assert.equal(now.revisions.layout,before.revisions.layout);
  await driver.command('pointer.move',{x:button.bounds.x+6,y:button.bounds.y+button.bounds.height/2});
  now=await driver.command('metrics');assert.equal(now.revisions.paint,before.revisions.paint+1);assert.equal(now.revisions.layout,before.revisions.layout);
  const childText=tree.find(n=>n.parent===button.node&&n.type==='text');
  await driver.command('pointer.move',{x:childText.bounds.x+childText.bounds.width/2,y:childText.bounds.y+childText.bounds.height/2});
  assert.equal((await driver.command('metrics')).revisions.paint,now.revisions.paint);
  let at=await driver.command('clock.advance',{ms:100});assert.equal(at.revisions.paint,now.revisions.paint);assert.equal(at.revisions.layout,now.revisions.layout);
  at=await driver.command('clock.advance',{ms:100});assert.equal(at.revisions.paint,now.revisions.paint+1);assert.equal(at.revisions.layout,now.revisions.layout+1);
  at=await driver.command('clock.advance',{ms:100});assert.equal(at.revisions.paint,now.revisions.paint+2);assert.equal(at.revisions.layout,now.revisions.layout+1);
  const exposed=await driver.command('surface.expose');assert.equal(exposed.revisions.paint,at.revisions.paint+1);assert.equal(exposed.revisions.layout,at.revisions.layout);
  const resized=await driver.command('resize',{width:1320,height:740});assert.equal(resized.revisions.paint,exposed.revisions.paint+1);assert.equal(resized.revisions.layout,exposed.revisions.layout+1);
  const focused=await driver.command('key.down',{key:'Tab'});assert.equal(focused.revisions.paint,resized.revisions.paint+1);assert.equal(focused.revisions.layout,resized.revisions.layout);
  await driver.command('key.up',{key:'Tab'});
  console.log('Native frame scheduling passed: 120 unchanged moves, hover/text ancestry, cursor-only, layout, timer paint, OS exposure, resize and focus through the shared driver');
  await driver.command('close');driver.disconnect();
  await new Promise((resolve,reject)=>{child.once('exit',code=>code===0?resolve():reject(Error('native exit '+code)));setTimeout(()=>reject(Error('close timeout')),5000).unref();});
}finally{
  driver?.disconnect();if(child?.exitCode===null)child.kill();
  run(process.execPath,['tools/build-ui.mjs'],{DRAFT1_ENTRY:'/examples/css/app.js'});
  run('zig',['build']);
}
