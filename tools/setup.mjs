// Fetch the exact QuickJS revision used by the native bridge.
import {existsSync,mkdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
process.chdir(fileURLToPath(new URL('../',import.meta.url)));
const pin='6a9fe9af5ca0bf7c49ae697edef44864272317d1';
function git(args){const r=spawnSync('git',args,{encoding:'utf8'}); if(r.status!==0) throw Error(r.stderr||r.error||'git failed'); return r.stdout.trim();}
mkdirSync('vendor',{recursive:true});
if(!existsSync('vendor/quickjs/.git')) git(['clone','https://github.com/quickjs-ng/quickjs.git','vendor/quickjs']);
if(git(['-C','vendor/quickjs','rev-parse','HEAD'])!==pin){
    if(git(['-C','vendor/quickjs','status','--porcelain'])) throw Error('QuickJS checkout has local changes; cannot change its revision');
    git(['-C','vendor/quickjs','fetch','origin',pin]);
    git(['-C','vendor/quickjs','checkout','--detach',pin]);
}
console.log(`QuickJS ready: ${pin}`);
