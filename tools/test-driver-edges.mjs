import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {resolve} from 'node:path';
import {build} from 'vite';
import {Driver} from './driver.mjs';
import {stopNative} from './native-process.mjs';
const release=process.argv.includes('--release'),opt=release?'ReleaseSafe':'Debug';
const compile=spawnSync('zig',['build','-Ddriver=true',...(release?['-Doptimize=ReleaseSafe','--prefix','zig-out/driver-release']:[])],{encoding:'utf8',timeout:1200000});assert.equal(compile.status,0,compile.stdout+compile.stderr);
const executable=release?'zig-out/driver-release/bin/windows.exe':'zig-out/bin/windows.exe';
const bundle='.zig-cache/driver-edges/ui-bundle.js';
await build({mode:'production',logLevel:'warn',build:{outDir:'.zig-cache/driver-edges',lib:{entry:resolve('tests/fixtures/driver-edges.jsx'),name:'DriverEdges',formats:['iife'],fileName:()=>'ui-bundle.js'}}});
await mkdir('docs/evidence',{recursive:true});
const captures=[];
for(const unaware of [false,true]){
  const pipe='driver-edges-'+process.pid+'-'+unaware,token=randomBytes(24).toString('hex');
  const env={...process.env};for(const k of Object.keys(env))if(k.startsWith('DRAFT1_HMR')||k.startsWith('SOLID_NATIVE'))delete env[k];
  Object.assign(env,{SOLID_NATIVE_PIPE:pipe,SOLID_NATIVE_TOKEN:token,SOLID_NATIVE_CONTROLLED:'1',SOLID_NATIVE_DRIVER_HIDDEN:'1',SOLID_NATIVE_DRIVER_SOURCE:resolve(bundle),...(unaware?{SOLID_NATIVE_TEST_DPI_UNAWARE:'1'}:{})});
  const child=spawn(executable,[],{env,windowsHide:true,stdio:['ignore','ignore','pipe']});let output='';child.stderr.on('data',x=>output+=x);let d;
  try{
    d=await Driver.connect({pipe,token});
    const node=async id=>(await d.tree()).find(n=>n.testId===id);
    const count=async()=>{const n=await node('count');return(await d.tree()).filter(x=>x.parent===n.node).map(x=>x.text).join('')};
    await d.command('click',{target:{testId:'transform'}});assert.equal(await count(),'count:1');
    await assert.rejects(()=>d.command('click',{target:{testId:'clipped'}}),/ObscuredTarget/);
    await assert.rejects(()=>d.command('click',{target:{testId:'occluded'}}),/ObscuredTarget/);
    await d.command('click',{target:{testId:'select'}});
    await d.command('click',{target:{testId:'beta'}});assert.equal((await node('select')).value,'b');
    await d.command('click',{target:{testId:'select'}});await d.command('key.down',{key:'ArrowUp'});await d.command('key.up',{key:'ArrowUp'});assert.equal((await node('select')).value,'a');
    await assert.rejects(()=>d.command('click',{target:{testId:'popup-child'}}),/TargetNotFound/);
    await d.command('click',{target:{testId:'popover-toggle'}});await d.command('click',{target:{testId:'popup-child'}});assert.equal(await count(),'count:2');
    await d.command('key.down',{key:'Escape'});await d.command('key.up',{key:'Escape'});await assert.rejects(()=>d.command('click',{target:{testId:'popup-child'}}),/TargetNotFound/);
    const removed=await node('removed');await d.command('click',{target:{testId:'remove'}});await d.command('pointer.down',{target:{testId:'removed'}});await d.command('clock.advance',{ms:10});
    await assert.rejects(()=>d.command('click',{target:{node:removed.node}}),/TargetNotFound/);await d.command('pointer.up',{x:removed.bounds.x+5,y:removed.bounds.y+5});assert.equal(await count(),'count:2');
    const moving=await node('moving');await d.command('click',{target:{testId:'reparent'}});await d.command('pointer.down',{target:{testId:'moving'}});await d.command('clock.advance',{ms:10});await d.command('pointer.up',{x:moving.bounds.x+5,y:moving.bounds.y+5});assert.equal(await count(),'count:2');
    const moved=await node('moving');assert.equal(moved.node,moving.node);assert.notEqual(moved.parent,moving.parent);assert.ok(moved.bounds.x>moving.bounds.x+100);
    await d.command('click',{target:{node:moving.node}});assert.equal(await count(),'count:3','execution resolves current reparented geometry');
    await d.command('surface.state',{value:'focus-gained'});await d.command('key.down',{key:'Control'});await d.command('pointer.down',{target:{testId:'moving'}});await d.command('surface.state',{value:'focus-lost'});
    const focus=await d.command('metrics');assert.equal(focus.input.pointerDown,false);assert.equal(focus.input.keysHeld,0);
    await d.command('click',{target:{testId:'timer'}});const future=await d.command('metrics');await d.command('surface.state',{value:'stale-wake'});const afterWake=await d.command('metrics');assert.equal(afterWake.appTime,future.appTime);assert.deepEqual(afterWake.pending,future.pending);assert.ok(!(await d.command('logs')).logs.lines.includes('edge-timer-fired'));
    const beforeZero=await d.command('metrics');await assert.rejects(()=>d.command('resize',{width:0,height:0}),/InvalidSize/);assert.deepEqual((await d.command('metrics')).viewport,beforeZero.viewport);
    await d.command('click',{target:{testId:'animate'}});await d.command('clock.advance',{ms:100});assert.ok(Math.abs((await node('motion')).opacity-.5)<.01);
    for(const [width,height] of [[800,600],[1200,700]]){
      await d.command('resize',{width,height});const before=await d.command('metrics');await d.tree('layout');const after=await d.command('metrics');assert.deepEqual(after.revisions,before.revisions,'inspection must not paint/layout');
      const path=resolve('.zig-cache/driver-edges',opt+'-'+unaware+'-'+width+'.png');const capture=await d.command('screenshot',{path});const png=await readFile(path);assert.equal(png.readUInt32BE(16),capture.viewport.framebufferWidth);assert.equal(png.readUInt32BE(20),capture.viewport.framebufferHeight);assert.equal(capture.capture.width,capture.viewport.framebufferWidth);assert.equal(capture.appTime,after.appTime);
      captures.push({unaware,viewport:capture.viewport,appTime:capture.appTime,motionOpacity:(await node('motion')).opacity,readback:capture.capture.readback});
    }
    const minimized=await d.command('surface.state',{value:'minimize'});assert.equal(minimized.viewport.minimized,true);await assert.rejects(()=>d.command('screenshot',{path:resolve('.zig-cache/driver-edges/minimized.png')}),/SurfaceUnavailable/);await d.command('surface.state',{value:'restore'});
    await d.command('close');d.disconnect();d=null;await new Promise((res,rej)=>{if(child.exitCode!==null)return child.exitCode===0?res():rej(Error(output));child.once('exit',code=>code===0?res():rej(Error(output)))});
    console.log('PASS native driver edge cases',opt,'DPI unaware='+unaware);
  }catch(error){throw Error(error.stack+'\nNATIVE:\n'+output)}finally{d?.disconnect();await stopNative(child)}
}
await writeFile('docs/evidence/driver-edges-'+opt+'.json',JSON.stringify({optimization:opt,passed:true,cases:['transformed','clipped','occluded','select pointer/keyboard','popover open/close','removed target','reparent between down/up and fresh resolution','focus loss cancels held input','stale OS wake rejected','zero size rejected before mutation','motion/layout capture','minimized capture refusal','DPI aware/unaware child windows','read-only no rendering'],captures},null,2)+'\n');
