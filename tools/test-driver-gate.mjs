import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {Driver} from './driver.mjs';
const pipe='solid-disabled-'+process.pid,token=randomBytes(24).toString('hex');
const child=spawn(process.argv[2]??'zig-out/no-driver/bin/windows.exe',[],{windowsHide:true,stdio:'ignore',env:{...process.env,SOLID_NATIVE_PIPE:pipe,SOLID_NATIVE_TOKEN:token,SOLID_NATIVE_CONTROLLED:'1'}});
try{
  await assert.rejects(()=>Driver.connect({pipe,token,timeout:750}),/ENOENT/);
  assert.equal(child.exitCode,null,'ordinary app remains running');
  // Close only the normal visible window belonging to this test-owned process.
  const close=spawnSync('powershell.exe',['-NoProfile','-Command',`$p=Get-Process -Id ${child.pid}; for($i=0;$i -lt 50 -and $p.MainWindowHandle -eq 0;$i++){Start-Sleep -Milliseconds 100;$p.Refresh()}; if(!$p.CloseMainWindow()){exit 1}`],{windowsHide:true,encoding:'utf8',timeout:10000});
  assert.equal(close.status,0,close.stderr);
  if(child.exitCode===null)await new Promise((resolve,reject)=>{child.once('exit',code=>code===0?resolve():reject(Error('native exit '+code)));setTimeout(()=>reject(Error('normal close timeout')),10000).unref();});
  assert.equal(child.exitCode,0);
  console.log('PASS ordinary ReleaseSafe host: no driver pipe, normal visible launch and close');
}finally{if(child.exitCode===null)child.kill();}
