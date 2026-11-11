import { createMemo, createSignal } from "solid-js";

export function Counter() {
  const [count, setCount] = createSignal(2);
  const doubleCount = createMemo(() => count() * 2);
  return (
    <column style={{ padding: 20, gap: 8 }}>
      <label>Count: {count()}</label>
      <label>Double Count: {doubleCount()}</label>
      <button onClick={() => setCount(count() + 1)}>Increment</button>
    </column>
  );
}

if (import.meta.hot) import.meta.hot.accept();
