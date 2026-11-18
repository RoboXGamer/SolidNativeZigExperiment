import {createSignal} from 'solid-js';
import {mountApp} from '@zig-ui/solid';
function App(){
  const [value,setValue]=createSignal('');
  const [opacity,setOpacity]=createSignal(1);
  const [transition,setTransition]=createSignal('opacity 200ms linear');
  const [time,setTime]=createSignal('idle');
  return <div style={{padding:20,gap:12}}>
    <input data-testid="entry" value={value()} onInput={e=>setValue(e.target.value)} />
    <button data-testid="animate" onClick={()=>{
      setOpacity(0);
      setTimeout(()=>console.log('unrelated timer'),10);
      setTime(String(performance.now()));
      setTimeout(()=>setTime(String(performance.now())),100);
      setTimeout(()=>setTime(String(performance.now())),200);
    }}>Animate</button>
    <button data-testid="retarget" onClick={()=>setOpacity(1)}>Retarget</button>
    <button data-testid="delayed" onClick={()=>{setTransition('opacity 200ms linear 100ms');setOpacity(1)}}>Delayed</button>
    <button data-testid="zero" onClick={()=>{setTransition('opacity 0ms');setOpacity(0)}}>Zero</button>
    <button data-testid="throw" onClick={()=>{setTime('before error');console.log('fixture partial progress');throw Error('fixture exception')}}>Throw</button>
    <div data-testid="motion" style={{width:100,height:100,backgroundColor:'#ff0000',opacity:opacity(),transition:transition()}} />
    <div data-testid="observation">{time()}</div>
    <button data-testid="disabled" disabled>Disabled</button>
    <button data-testid="duplicate">A</button><button data-testid="duplicate">B</button>
  </div>;
}
mountApp(App);
