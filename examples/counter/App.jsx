import { createSignal } from "solid-js";
import "./app.css";

export default function App() {
  const [count, setCount] = createSignal(0);
  return (
    <div class="counter">
      <div>Solid + CSS. Native.</div>
      <button onClick={() => setCount(count() + 1)}>
        {`Clicked ${count()} times`}
      </button>
    </div>
  );
}
