import { createSignal, onSettled } from "solid-js";
import { mountApp } from "@zig-ui/solid";
import { runStableContract } from "../solid-stable-contract.js";

function App() {
  const [count, setCount] = createSignal(0);
  const refs = [];
  onSettled(() => {
    if (refs.map(([name]) => name).join(",") !== "first,second" ||
        refs.some(([, node]) => node !== refs[0][1] || node.type !== "button")) {
      throw Error("Compiled JSX refs did not receive the retained button in order");
    }
  });
  return <div>
    <button ref={[node => refs.push(["first", node]), [node => refs.push(["second", node])]]}
      onClick={() => setCount(count() + 1)}>{`Stable ${count()}`}</button>
  </div>;
}

mountApp(App);
runStableContract().then(result => {
  const readButton = () => JSON.parse(uiSnapshot()).children[0].children[0];
  const button = readButton();
  uiDispatchClick(button.id);
  __uiSolid.flush();
  const updated = readButton();
  if (updated.id !== button.id || updated.children.map(node => node.text).join("") !== "Stable 1") {
    throw Error("Compiled button and the host did not share the same Solid runtime");
  }
  console.log(`PASS Solid 2 stable contracts: ${result.checks} checks (development=${result.development})`);
}).catch(error => {
  console.error("STABLE_CONTRACT_FAILURE", error.stack || error);
});
