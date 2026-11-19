import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import net from 'node:net';
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {build} from 'vite';
import {stopNative} from './native-process.mjs';
const executable=process.argv[2]??'zig-out/driver-disabled/bin/windows.exe';
if(!process.argv[2]){
  const bundle='.zig-cache/driver-gate/ui-bundle.js';
  await build({mode:'production',logLevel:'warn',build:{outDir:'.zig-cache/driver-gate',lib:{entry:resolve('tests/fixtures/driver-edges.jsx'),name:'GateFixture',formats:['iife'],fileName:()=>'ui-bundle.js'}}});
  const result=spawnSync('zig',['build','-Ddriver=false','-Doptimize=ReleaseSafe','-Dui-bundle='+bundle,'--prefix','zig-out/driver-disabled'],{encoding:'utf8',timeout:1200000});assert.equal(result.status,0,result.stdout+result.stderr);
}
const pipe='disabled-driver-'+process.pid;
const env={...process.env};for(const k of Object.keys(env))if(k.startsWith('DRAFT1_HMR')||k.startsWith('SOLID_NATIVE'))delete env[k];
Object.assign(env,{SOLID_NATIVE_PIPE:pipe,SOLID_NATIVE_TOKEN:'test-disabled',SOLID_NATIVE_CONTROLLED:'1',SOLID_NATIVE_DRIVER_HIDDEN:'1',SOLID_NATIVE_DRIVER_SOURCE:'nonexistent.js'});
const child=spawn(executable,[],{windowsHide:false,env,stdio:['ignore','pipe','pipe']});
let output='';child.stdout.on('data',x=>output+=x);child.stderr.on('data',x=>output+=x);
try{
  await new Promise(r=>setTimeout(r,5000));assert.equal(child.exitCode,null,output);
  await assert.rejects(()=>new Promise((res,rej)=>{const s=net.connect('\\\\.\\pipe\\'+pipe);s.once('connect',()=>{s.destroy();res()});s.once('error',rej)}),/ENOENT|EACCES|ECONNREFUSED/);
  const closed=new Promise((res,rej)=>{const t=setTimeout(()=>rej(Error('normal close timed out')),10000);child.once('exit',code=>{clearTimeout(t);code===0?res():rej(Error(output))})});
  const close=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`$p=Get-Process -Id ${child.pid}; if ($p.MainWindowHandle -eq 0 -or -not $p.CloseMainWindow()) { exit 1 }`],{encoding:'utf8',windowsHide:true});assert.equal(close.status,0,close.stdout+close.stderr);await closed;
  assert.ok(!/Could not|failed:|ERROR:/.test(output),output);
  await mkdir('docs/evidence',{recursive:true});await writeFile('docs/evidence/driver-release-gate.json',JSON.stringify({passed:true,optimization:'ReleaseSafe',driver:false,profile:false,endpointAbsent:true,visibleWindowOpenedAndClosedNormally:true,driverEnvironmentIgnored:true},null,2)+'\n');
  console.log('PASS ordinary ReleaseSafe: visible launch/normal close, no endpoint despite driver environment');
}finally{await stopNative(child)}
