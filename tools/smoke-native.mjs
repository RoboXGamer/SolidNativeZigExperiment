import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
process.chdir(fileURLToPath(new URL('../',import.meta.url)));
const r=spawnSync('zig-out/bin/windows.exe',[],{encoding:'utf8',timeout:15000,env:{...process.env,SOLID_NATIVE_SMOKE:'1'}});
const output=(r.stdout||'')+(r.stderr||'');
process.stdout.write(output);
if(r.error || r.status!==0 || !output.includes('Native application smoke completed:') || /\(err\)|ERROR:|Could not|failed:/i.test(output)) {
    console.error(r.error || 'Native application smoke failed'); process.exit(1);
}
