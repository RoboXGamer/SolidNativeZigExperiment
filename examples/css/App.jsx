import { createSignal } from "solid-js";
import "./styles/demo.css";
export default function CssDemo() {
  const [active, setActive] = createSignal(false);
  return (
    <div id="css-demo">
      <div class="title">Solid + Zig · CSS files</div>
      <div class="description">
        Edit examples/css/styles/demo.css while pnpm dev is running.
      </div>
      <div class="samples">
        <div class="card" id="specificity">
          <div>ID selector wins</div>
          <div class="small">Color and font inherited by text</div>
        </div>
        <div class={active() ? "card active" : "card"}>
          <div>Reactive class</div>
          <div class="small">Click the button to change my style</div>
        </div>
        <div class="card image">
          <div>Imported CSS + image URL</div>
        </div>
      </div>
      <button class="toggle" onClick={() => setActive(!active())}>
        Toggle active class
      </button>
      <div class="description">
        Class / ID · specificity · !important · custom properties · inheritance
        · local @import · local image URLs
      </div>
    </div>
  );
}
