import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomBytes,createHash} from 'node:crypto';
import {build} from 'vite';
const debug=process.argv.includes('--debug'),opt=debug?'Debug':'ReleaseSafe';
const bundle='.zig-cache/clock-profile/ui-bundle.js';
await build({mode:'production',logLevel:'warn',build:{outDir:'.zig-cache/clock-profile',lib:{entry:resolve('tests/fixtures/clock-profile.jsx'),name:'ClockProfile',formats:['iife'],fileName:()=>'ui-bundle.js'}}});
const variants=[false,true];
for(const driver of variants){const args=['build','-Dhost-profile=true','-Ddriver='+driver,'-Doptimize='+opt,'-Dui-bundle='+bundle,'--prefix','zig-out/profile-'+driver];const result=spawnSync('zig',args,{encoding:'utf8',timeout:1200000});assert.equal(result.status,0,result.stdout+result.stderr+result.error);}
const runs=[];
const sha256=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const artifacts={bundleSha256:sha256(bundle),binaries:variants.map(driver=>({driver,sha256:sha256('zig-out/profile-'+driver+'/bin/windows.exe')}))};
for(let repeat=0;repeat<2;repeat++)for(const driver of variants){
  const env={...process.env};for(const k of Object.keys(env))if(k.startsWith('DRAFT1_HMR')||k.startsWith('SOLID_NATIVE'))delete env[k];
  Object.assign(env,{SOLID_NATIVE_DRIVER_SOURCE:resolve(bundle),SOLID_NATIVE_DRIVER_HIDDEN:'1',SOLID_NATIVE_CONTROLLED:'1',PREFERS_COLOR_SCHEME:'light',PREFERS_REDUCED_MOTION:'no_preference',SOLID_NATIVE_PIPE:'clock-profile-'+process.pid+'-'+repeat,SOLID_NATIVE_TOKEN:randomBytes(24).toString('hex')});
  const result=spawnSync('zig-out/profile-'+driver+'/bin/windows.exe',[],{windowsHide:true,encoding:'utf8',timeout:180000,env});
  const output=result.stdout+result.stderr;assert.equal(result.status,0,output+result.error);
  const json=output.match(/HOST_PROFILE (\{[^\n]+\})/)?.[1];assert.ok(json,output);
  assert.match(output,/HOST_PROFILE_TEARDOWN 0 0/);
  const data=JSON.parse(json.replace(/"sceneHash":(\d+)/g,'"sceneHash":"$1"'));
  assert.equal(data.stages.find(s=>s.name==='noop').paints,0);assert.equal(data.stages.find(s=>s.name==='noop').layouts,0);
  assert.equal(data.stages.find(s=>s.name==='paint').layouts,0);assert.equal(data.stages.find(s=>s.name==='paint').paints,50);
  assert.equal(data.stages.find(s=>s.name==='layout').layouts,50);
  assert.equal(data.stages.find(s=>s.name==='inspection').paints,0);assert.equal(data.stages.find(s=>s.name==='inspection').layouts,0);
  assert.equal(data.stages.at(-1).quickjs.roots,0);
  runs.push({repeat,...data,teardown:{nativeBytes:0,vmBytes:0}});
  console.log('PASS full host',opt,'driver='+driver,'repeat='+repeat);
}
for(let i=0;i<runs.length;i+=2){assert.deepEqual(runs[i].viewport,runs[i+1].viewport);assert.deepEqual(runs[i].stages.map(s=>[s.name,s.appTime,s.sceneHash,s.paints,s.layouts,s.inspectionBytes]),runs[i+1].stages.map(s=>[s.name,s.appTime,s.sceneHash,s.paints,s.layouts,s.inspectionBytes]));}
mkdirSync('docs/evidence',{recursive:true});writeFileSync('docs/evidence/clock-full-host-'+opt+'.json',JSON.stringify({date:'2026-11-19',source:spawnSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim(),sourceTreeDirty:spawnSync('git',['status','--porcelain'],{encoding:'utf8'}).stdout.trim().length>0,artifacts,optimization:opt,baseline:'same current host with driver compiled out',candidate:'same current host with driver enabled and listening',workload:'cold startup; 120 unchanged moves; 50 paint changes; 50 layout changes; 20 bounded scene inspection pages; 200ms frozen-clock idle',scope:'Full native host in both cases with identical allocator probes and controlled app data; compares optional driver overhead. Historical JS Map vs Zig scheduling comparison is separately scoped. C/OS/GPU allocations bypassing the wrapper are excluded.',runs},null,2)+'\n');
