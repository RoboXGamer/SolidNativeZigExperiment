// JSX is compiled by Solid's universal compiler, not React's automatic runtime.
export function jsx() {
  throw new Error("Compile native JSX with @solidjs/vite-plugin and generate: 'universal'");
}
export const jsxs = jsx;
export const jsxDEV = jsx;
export const Fragment = props => props.children;
