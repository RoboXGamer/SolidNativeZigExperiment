import {createSignal,Show} from 'solid-js';
import {mountApp} from '@zig-ui/solid';
import {insertNode} from '@zig-ui/solid/renderer';
function App(){
  const [count,setCount]=createSignal(0),[present,setPresent]=createSignal(true),[opacity,setOpacity]=createSignal(1);
  let moving,destination;
  const hit=()=>setCount(count()+1);
  const box=(left,top,width=100,height=30)=>({position:'absolute',left,top,width,height});
  return <div style={{position:'relative',width:700,height:600}}>
    <label testId="count" style={box(0,0)}>count:{count()}</label>
    <button testId="transform" onClick={hit} style={{...box(10,40),transform:'translateX(60px)'}}>transform</button>
    <div style={{...box(10,90,100,20),overflow:'hidden'}}><button testId="clipped" onClick={hit} style={box(0,30)}>clipped</button></div>
    <button testId="occluded" onClick={hit} style={box(10,150)}>under</button>
    <button testId="cover" style={box(10,150)}>cover</button>
    <select testId="select" style={box(200,40)}><option value="a">Alpha</option><option testId="beta" value="b">Beta</option></select>
    <button testId="popover-toggle" popovertarget="popup" style={box(200,150)}>popup</button>
    <div id="popup" popover="auto" style={box(330,150,130,50)}><button testId="popup-child" onClick={hit}>inside</button></div>
    <button testId="remove" onClick={()=>setTimeout(()=>setPresent(false),10)} style={box(10,210)}>remove later</button>
    <Show when={present()}><button testId="removed" onClick={hit} style={box(200,210)}>removed</button></Show>
    <button testId="reparent" onClick={()=>setTimeout(()=>insertNode(destination,moving),10)} style={box(10,270)}>move later</button>
    <div style={box(200,270,120,40)}><button ref={moving} testId="moving" onClick={hit} style={{width:100,height:30}}>moving</button></div>
    <div ref={destination} style={box(400,270,120,40)}/>
    <button testId="animate" onClick={()=>setOpacity(0)} style={box(10,340)}>animate</button>
    <div testId="motion" style={{...box(200,340,100,100),opacity:opacity(),transition:'opacity 200ms linear',backgroundColor:'#ff0000'}}/>
    <button testId="timer" onClick={()=>setTimeout(()=>console.log('edge-timer-fired'),100)} style={box(10,480)}>timer</button>
  </div>;
}
mountApp(App);
