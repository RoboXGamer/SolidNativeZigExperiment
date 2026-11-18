import { For, Show, createSignal, type Component } from "solid-js";
import { mountApp, type NativeNode, type NativeEvent, type NativeStyle } from "@zig-ui/solid";

const style: NativeStyle = { display: "flex", flexDirection: "column", gap: 12, padding: "16px", color: "white" };
const App: Component = () => {
  const [count, setCount] = createSignal(0);
  let element: NativeNode | undefined;
  const click = (event: NativeEvent) => {
    const id: number = event.currentTarget.id;
    event.stopPropagation();
    setCount(value => value + id);
    // @ts-expect-error Native events do not expose browser mouse coordinates.
    event.clientX;
  };
  return <div id="typed-native" class="panel" classList={{ active: count() > 0 }} style={style}>
    <button ref={[node => { element = node; }, [node => { const id: number = node.id; void id; }]]} onClick={click}>
      {`Count ${count()}`}
    </button>
    <input value={String(count())} onInput={event => { const value: string | undefined = event.target.value; void value; }} />
    <Show when={count() > 0} fallback={<text>Zero</text>}><label>Positive</label></Show>
    <For each={[1, 2]}>{value => <text>{value}</text>}</For>
  </div>;
};

mountApp(App);
// @ts-expect-error Unsupported native style values must be rejected.
const invalid: NativeStyle = { flexDirection: "diagonal" };
// @ts-expect-error Native JSX must not silently inherit arbitrary DOM tags.
const browserOnly = <iframe src="https://example.com" />;
void invalid;
void browserOnly;
