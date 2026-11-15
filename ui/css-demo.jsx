import { createSignal } from "solid-js";
import "./styles/demo.css";
export default function CssDemo() {
  const [active, setActive] = createSignal(false);
  return (
    <column id="css-demo">
      <label class="title">Solid + Zig · CSS files</label>
      <label class="description">
        Edit ui/styles/demo.css while pnpm dev is running.
      </label>
      <row class="samples">
        <column class="card" id="specificity">
          <label>ID selector wins</label>
          <label class="small">Color and font inherited by text</label>
        </column>
        <column class={active() ? "card active" : "card"}>
          <label>Reactive class</label>
          <label class="small">Click the button to change my style</label>
        </column>
        <column class="card image">
          <label>Imported CSS + image URL</label>
        </column>
      </row>
      <button class="toggle" onClick={() => setActive(!active())}>
        Toggle active class
      </button>
      <label class="description">
        Class / ID · specificity · !important · custom properties · inheritance
        · local @import · local image URLs
      </label>
    </column>
  );
}
