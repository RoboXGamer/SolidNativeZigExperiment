import net from 'node:net';
import {fileURLToPath} from 'node:url';

/** One controller connection. Never retries a mutation after a lost reply. */
export class Driver {
  constructor(socket) {
    this.socket=socket; this.id=0; this.pending=[]; this.bytes=Buffer.alloc(0);this.nodeGraphs=new Map();
    socket.on('data',chunk=>{
      this.bytes=Buffer.concat([this.bytes,chunk]);
      if(this.bytes.length>65536&&!this.bytes.includes(10)){socket.destroy(Error('Driver response exceeds 64 KiB'));return;}
      for(let at;(at=this.bytes.indexOf(10))>=0;){
        const line=this.bytes.subarray(0,at);this.bytes=this.bytes.subarray(at+1);
        const waiter=this.pending.shift();if(!waiter)continue;
        clearTimeout(waiter.timer);
        try{waiter.resolve(JSON.parse(line));}catch(e){waiter.reject(e);}
      }
    });
    const fail=error=>{for(const p of this.pending.splice(0)){clearTimeout(p.timer);p.reject(error);} };
    socket.on('error',fail);socket.on('close',()=>fail(Error('Driver disconnected; result uncertain. Mutations are never retried.')));
  }
  static async connect({pipe=process.env.SOLID_NATIVE_PIPE,token=process.env.SOLID_NATIVE_TOKEN,timeout=10000}={}) {
    if(!pipe||!token)throw Error('Set SOLID_NATIVE_PIPE and SOLID_NATIVE_TOKEN');
    const deadline=Date.now()+timeout;
    let socket;
    while(true){
      try{socket=await new Promise((resolve,reject)=>{const s=net.connect(`\\\\.\\pipe\\${pipe}`);s.once('error',reject);s.once('connect',()=>{s.removeListener('error',reject);resolve(s);});});break;}
      catch(e){if(Date.now()>=deadline)throw e;await new Promise(r=>setTimeout(r,25));}
    }
    const driver=new Driver(socket);
    let hello;
    try{hello=await driver.command('hello',{token});}catch(e){socket.destroy();throw e;}
    driver.session=hello.session;driver.generation=hello.generation;driver.hello=hello;
    return driver;
  }
  raw(envelope,{fragment=false}={}) {
    const bytes=Buffer.isBuffer(envelope)?envelope:typeof envelope==='string'?Buffer.from(envelope):Buffer.from(JSON.stringify(envelope)+'\n');
    if(bytes.length>65537)return Promise.reject(Error('Request exceeds 64 KiB'));
    return new Promise((resolve,reject)=>{
      const waiter={resolve,reject,timer:setTimeout(()=>{this.socket.destroy();reject(Error('Driver watchdog expired; result uncertain'));},20000)};
      this.pending.push(waiter);
      if(fragment){this.socket.write(bytes.subarray(0,7));this.socket.write(bytes.subarray(7,19));this.socket.write(bytes.subarray(19));}else this.socket.write(bytes);
    });
  }
  async command(cmd,args={}) {
    if(args.target?.node!=null){const t=args.target,identity=this.nodeGraphs.get(t.node);if((t.graph??identity?.graph)==null||(t.generation??identity?.generation)==null)throw Error('MissingTargetIdentity: discover nodes with tree() or supply graph/generation');args={...args,target:{...t,graph:t.graph??identity?.graph,generation:t.generation??identity?.generation}};}
    const result=await this.raw({version:1,id:++this.id,cmd,session:this.session,generation:this.generation,...args}).catch(error=>{error.message=cmd+': '+error.message;throw error;});
    if(result.graph!=null)this.graph=result.graph;
    if(result.error)throw Object.assign(Error(result.error),{receipt:result});
    return result;
  }
  async tree(cmd='tree') {
    const nodes=[];let cursor;this.nodeGraphs.clear();
    do {const page=await this.command(cmd,{...(cursor?{cursor}:{}),limit:64});for(const n of page.nodes){n.graph=page.graph;n.generation=page.generation;if(this.nodeGraphs.size<4096)this.nodeGraphs.set(n.node,{graph:page.graph,generation:page.generation});}nodes.push(...page.nodes);cursor=page.cursor;}while(cursor);
    return nodes;
  }
  disconnect(){this.socket.end();}
}

if(process.argv[1]===fileURLToPath(import.meta.url)) {
  const [cmd='hello',json='{}']=process.argv.slice(2);
  const driver=await Driver.connect();
  try{console.log(JSON.stringify(cmd==='hello'?driver.hello:await driver.command(cmd,JSON.parse(json)),null,2));}
  finally{driver.disconnect();}
}
