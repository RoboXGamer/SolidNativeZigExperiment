import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
import {Driver} from './driver.mjs';
import {resolve} from 'node:path';
function run(cmd,args,env={}){const p=spawnSync(cmd,args,{encoding:'utf8',timeout:600000,env:{...process.env,...env}});if(p.status!==0)throw Error(`${p.stdout}${p.stderr}${p.error??''}`);}
const measurements=[];
const optimize=process.argv.includes('--release')?['-Doptimize=ReleaseSafe']:[];
const prefix=optimize.length?['--prefix','zig-out/driver-release']:[];
const executable=optimize.length?'zig-out/driver-release/bin/windows.exe':'zig-out/bin/windows.exe';
run('zig',['build','-Ddriver=true',...optimize,...prefix]);
for(const example of ['css','tictactoe','fixture']){
  run(process.execPath,['tools/build-ui.mjs',...(example==='fixture'?[]:['--example',example])],example==='fixture'?{DRAFT1_ENTRY:'/tests/fixtures/driver.jsx'}:{});
  const pipe=`solid-driver-${process.pid}-${example}`,token=randomBytes(24).toString('hex');
  const child=spawn(executable,[],{windowsHide:true,env:{...process.env,SOLID_NATIVE_PIPE:pipe,SOLID_NATIVE_TOKEN:token,SOLID_NATIVE_CONTROLLED:'1',SOLID_NATIVE_DRIVER_HIDDEN:'1',SOLID_NATIVE_DRIVER_SOURCE:resolve('src/ui-bundle.js')},stdio:['ignore','ignore','pipe']});
  let diagnostics='';child.stderr.on('data',d=>diagnostics+=d);
  let driver;
  try {
    await assert.rejects(()=>Driver.connect({pipe,token:'incorrect-token',timeout:10000}),/AuthenticationFailed/);
    driver=await Driver.connect({pipe,token});
    assert.ok(driver.hello.preferences.includes('color-scheme'));assert.ok(driver.hello.keys.includes('Tab'));
    assert.ok((await driver.raw('\n')).error);
    assert.equal((await driver.raw(Buffer.from([0xff,10]))).error,'InvalidUtf8');
    const raw=await driver.raw({version:1,id:++driver.id,cmd:'metrics',session:driver.session,generation:driver.generation},{fragment:true});assert.equal(raw.error,null);
    const duplicate=await driver.raw({version:1,id:driver.id,cmd:'metrics',session:driver.session,generation:driver.generation});assert.deepEqual(duplicate,raw);
    const bad=await driver.raw({version:2,id:++driver.id,cmd:'metrics'});assert.equal(bad.error,'UnsupportedVersion');
    const wrong=await driver.raw({version:1,id:++driver.id,cmd:'pointer.down',session:driver.session,generation:0,x:0,y:0});assert.equal(wrong.error,'StaleRuntime');
    let nodes=await driver.tree();assert.ok(nodes.length>10);
    const page=await driver.command('layout',{limit:1});assert.ok(page.cursor);
    await driver.command('resize',{width:1279,height:720});
    await assert.rejects(()=>driver.command('layout',{cursor:page.cursor,limit:1}),/StaleCursor/);
    await driver.command('resize',{width:1280,height:720});
    const pipelined=await Promise.all([0,1,2].map(()=>driver.raw({version:1,id:++driver.id,cmd:'metrics',session:driver.session,generation:driver.generation})));
    assert.ok(pipelined.every(r=>r.error===null));
    if(example==='tictactoe') {
      const start=nodes.find(n=>n.type==='text'&&n.text==='NEW GAME (VS CPU)');assert.ok(start);
      await driver.command('click',{target:{node:start.parent}});
      nodes=await driver.tree();const cell=nodes.find(n=>n.name==='Cell 1');assert.ok(cell);
      await driver.command('click',{target:{node:cell.node}});
      const before=await driver.tree();assert.equal(before.filter(n=>/^Cell \d:/.test(n.name)).length,1);
      const settled=await driver.command('settle');assert.equal(settled.appTime,0);assert.equal(settled.pending.nextDeadlineMs,350);
      const at349=await driver.command('clock.advance',{ms:349});assert.equal(at349.appTime,349);assert.equal(at349.pending.nextDeadlineMs,350);
      assert.equal((await driver.tree()).filter(n=>/^Cell \d:/.test(n.name)).length,1);
      const at350=await driver.command('clock.advance',{ms:1});assert.equal(at350.appTime,350);
      assert.equal((await driver.tree()).filter(n=>/^Cell \d:/.test(n.name)).length,2);
      console.log('Actual Solid/QuickJS/native CPU move: pending at 349 ms, committed at 350 ms');
    }else if(example==='css'){
      const button=nodes.find(n=>n.type==='button');assert.ok(button);
      await driver.command('click',{target:{node:button.node}});
      await driver.command('pointer.move',{x:-10,y:-10});
      const initial=await driver.command('metrics');
      for(let i=0;i<120;i++)await driver.command('pointer.move',{x:-10-i,y:-10});
      const unchanged=await driver.command('metrics');assert.equal(unchanged.revisions.paint,initial.revisions.paint);assert.equal(unchanged.revisions.layout,initial.revisions.layout);
      await driver.command('resize',{width:1000,height:700});
      await driver.command('prefer',{preference:'color-scheme',value:'dark'});await driver.command('reset');
      console.log('Shared input: CSS click, 120 unchanged moves without layout/paint, resize/preferences');
    }else{
      await driver.command('click',{target:{testId:'entry'}});
      await driver.command('type',{text:'Unicode 😀 "quotes"'});
      const entry=(await driver.tree()).find(n=>n.testId==='entry');assert.equal(entry.value,'Unicode 😀 "quotes"');
      await driver.command('type',{text:'\nignored'});
      assert.equal((await driver.tree()).find(n=>n.testId==='entry').value,entry.value);
      await assert.rejects(()=>driver.command('click',{target:{testId:'disabled'}}),/DisabledTarget/);
      await assert.rejects(()=>driver.command('click',{target:{testId:'duplicate'}}),/AmbiguousTarget/);
      await driver.command('clock.advance',{ms:1000}); // a fresh animation must not inherit idle time
      await driver.command('click',{target:{testId:'animate'}});
      const pose=async expected=>assert.ok(Math.abs((await driver.tree()).find(n=>n.testId==='motion').opacity-expected)<.01,`expected native opacity ${expected}`);
      await pose(1);
      const at0=await driver.command('metrics');assert.equal(at0.appTime,1000);
      await driver.command('clock.advance',{ms:100});
      await pose(.5);
      const observed=(await driver.tree()).find(n=>n.testId==='observation');
      assert.equal((await driver.tree()).find(n=>n.parent===observed.node&&n.type==='text').text,'1100');
      await driver.command('clock.advance',{ms:100});
      await pose(0);
      const at200=await driver.command('metrics');assert.equal(at200.appTime,1200);
      assert.equal(at200.revisions.paint-at0.revisions.paint,12,'unrelated timer must not add a motion sample/paint');
      const read=await driver.command('metrics');assert.equal(read.revisions.paint,at200.revisions.paint);assert.equal(read.revisions.layout,at200.revisions.layout);
      await driver.command('click',{target:{testId:'retarget'}});
      await driver.command('clock.advance',{ms:100});await pose(.5);
      await driver.command('click',{target:{testId:'animate'}});await pose(.5);
      await driver.command('clock.advance',{ms:100});await pose(.25);
      await driver.command('clock.advance',{ms:100});await pose(0);
      await driver.command('click',{target:{testId:'delayed'}});await pose(0);
      await driver.command('clock.advance',{ms:100});await pose(0);
      await driver.command('clock.advance',{ms:100});await pose(.5);
      await driver.command('clock.advance',{ms:100});await pose(1);
      await driver.command('click',{target:{testId:'zero'}});await pose(0);
      await assert.rejects(()=>driver.command('click',{target:{testId:'throw'}}),e=>e.message==='JavaScriptEvaluationFailed'&&e.receipt.appTime===1800);
      assert.ok((await driver.command('logs')).logs.lines.includes('fixture partial progress'));
      await driver.command('key.down',{key:'Control'});
      await driver.command('pointer.down',{target:{testId:'entry'}});
      const oldSession=driver.session;
      driver.disconnect();
      driver=await Driver.connect({pipe,token});
      assert.notEqual(driver.session,oldSession);
      assert.equal(driver.hello.input.pointerDown,false);assert.equal(driver.hello.input.keysHeld,0);
      const stale=await driver.raw({version:1,id:++driver.id,cmd:'click',session:oldSession,generation:driver.generation,x:10,y:10});assert.equal(stale.error,'InvalidSession');
      const evictedId=driver.id;
      for(let i=0;i<17;i++)await driver.command('metrics');
      assert.equal((await driver.raw({version:1,id:evictedId,cmd:'click',session:driver.session,generation:driver.generation,x:10,y:10})).error,'ResultUncertain');
      const disconnected=new Promise(resolve=>driver.socket.once('close',resolve));
      driver.socket.write(Buffer.alloc(65538,0x61));await disconnected;
      driver=await Driver.connect({pipe,token});
      console.log('Shared input: Unicode/quotes/newlines, ambiguity/disabled rejection, JS/native motion after idle');
    }
    mkdirSync('.zig-cache/driver-captures',{recursive:true});
    const capture=await driver.command('screenshot',{path:`.zig-cache/driver-captures/${example}.png`});assert.equal(capture.evidence,'gpu-readback');
    const png=readFileSync(capture.capture.path);assert.equal(png.readUInt32BE(16),capture.capture.width);assert.equal(png.readUInt32BE(20),capture.capture.height);
    const samples=[];
    for(let i=0;i<50;i++){const start=performance.now();await driver.command('metrics');samples.push(performance.now()-start);}
    const idleStart=await driver.command('metrics');await new Promise(r=>setTimeout(r,1200));const idleEnd=await driver.command('metrics');
    assert.equal(idleEnd.revisions.layout,idleStart.revisions.layout);assert.equal(idleEnd.revisions.paint,idleStart.revisions.paint);
    assert.ok(idleEnd.real.hostTurns-idleStart.real.hostTurns<1000,'idle must enter event waiting; receipts record external wakes');
    samples.sort((a,b)=>a-b);measurements.push({example,optimize:optimize.length?'ReleaseSafe':'Debug',p50:samples[25],p95:samples[47],p99:samples[49],failures:0,scheduler:capture.metrics,quickjs:capture.quickjs,native:capture.native,driverStorageBytes:capture.driverStorageBytes,idle:{wallNs:idleEnd.real.monotonicNs-idleStart.real.monotonicNs,cpuNs:idleEnd.real.cpuNs-idleStart.real.cpuNs,hostTurns:idleEnd.real.hostTurns-idleStart.real.hostTurns}});
    const close=await driver.command('close');assert.equal(close.error,null);driver.disconnect();
    await new Promise((resolve,reject)=>{child.once('exit',code=>code===0?resolve():reject(Error(diagnostics)));setTimeout(()=>reject(Error('Native close timeout')),5000).unref();});
  }catch(e){throw Error(`${example}: ${e.stack}\n${diagnostics}`);}
  finally{driver?.disconnect();if(child.exitCode===null)child.kill();}
}
console.log(JSON.stringify(measurements,null,2));
writeFileSync('.zig-cache/driver-measurements.json',JSON.stringify(measurements,null,2)+'\n');
