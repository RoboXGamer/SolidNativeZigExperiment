import {mountApp} from '@zig-ui/solid';
import {createSignal,For,onCleanup} from 'solid-js';
function App(){
  const [paint,setPaint]=createSignal(false),[width,setWidth]=createSignal(100);
  let p=0,l=0;
  const paintTimer=setInterval(()=>{setPaint(++p%2===1);if(p===50)clearInterval(paintTimer)},1);
  let layoutTimer;
  const start=setTimeout(()=>{setWidth(110);l=1;layoutTimer=setInterval(()=>{setWidth(++l%2?110:100);if(l===50)clearInterval(layoutTimer)},1)},51);
  onCleanup(()=>{clearInterval(paintTimer);clearTimeout(start);clearInterval(layoutTimer)});
  return <div style={{padding:10,gap:2}}><div style={{width:width(),height:20,backgroundColor:paint()?'#445566':'#112233'}} />
    <For each={Array.from({length:128},(_,i)=>i)}>{i=><div style={{width:80,height:3,backgroundColor:'#223344'}}>{i}</div>}</For>
  </div>;
}
mountApp(App);
