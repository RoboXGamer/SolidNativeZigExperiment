import { createSignal } from "solid-js";

export function Counter() {
  const [count, setCount] = createSignal(50);
  return (
    <column>
      <label>Count: {count()}</label>
      <button onClick={() => setCount(count() + 1)}>Increment</button>
    </column>
  );
}

if (import.meta.hot) import.meta.hot.accept();
