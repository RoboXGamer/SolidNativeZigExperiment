import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {stopNative} from './native-process.mjs';
const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-Command','pnpm dev --example tictactoe'],{windowsHide:true,env:{...process.env,DRAFT1_VITE_PORT:String(20000+Math.floor(Math.random()*20000))},stdio:['ignore','pipe','pipe']});
let output='';child.stdout.on('data',x=>output+=x);child.stderr.on('data',x=>output+=x);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
try{
  const deadline=performance.now()+600000;let receipt,manifest;
  while(performance.now()<deadline){
    assert.equal(child.exitCode,null,output);
    const path=output.match(/; session (.+session\.json)/)?.[1]?.trim();
    if(path){try{manifest=JSON.parse(await readFile(path,'utf8'));receipt=JSON.parse(await readFile(manifest.status,'utf8'))}catch{}}
    if(receipt?.phase==='presented')break;
    await delay(100);
  }
  assert.equal(receipt?.phase,'presented',output);assert.equal(manifest.entry,'/examples/tictactoe/app.js');
  assert.match(manifest.bundle,/^[A-Za-z]:[\\/]/,'the dev manifest must exercise an absolute Windows bundle path');
  await delay(5000);assert.equal(child.exitCode,null,output);
  const close=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`$all=Get-CimInstance Win32_Process; $owned=@(${child.pid}); do { $next=@($all | Where-Object { $_.ParentProcessId -in $owned -and $_.ProcessId -notin $owned } | ForEach-Object ProcessId); $owned+=$next } while ($next.Count -gt 0); $windows=@($all | Where-Object { $_.ProcessId -in $owned -and $_.Name -eq 'windows.exe' }); if ($windows.Count -ne 1) { exit 1 }; $p=Get-Process -Id $windows[0].ProcessId; if ($p.MainWindowHandle -eq 0 -or -not $p.CloseMainWindow()) { exit 2 }`],{encoding:'utf8',windowsHide:true,timeout:15000});
  assert.equal(close.status,0,close.stdout+close.stderr+output);
  const end=performance.now()+15000;while(child.exitCode===null&&performance.now()<end)await delay(50);assert.equal(child.exitCode,0,output);
  assert.ok(!/panic:|ERROR:|Could not|ELIFECYCLE/.test(output),output);
  await mkdir('docs/evidence',{recursive:true});await writeFile('docs/evidence/dev-tictactoe-launch.json',JSON.stringify({passed:true,command:'pnpm dev --example tictactoe',absoluteBundlePath:true,nativeReceipt:receipt,visibleWindowStayedOpenMs:5000,normalClose:true,producerExit:child.exitCode},null,2)+'\n');
  console.log('PASS actual pnpm dev --example tictactoe: absolute bundle path, presented native graph, visible launch and normal close');
}finally{await stopNative(child)}
