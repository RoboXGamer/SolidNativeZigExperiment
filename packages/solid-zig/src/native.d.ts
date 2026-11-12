import type { Component, Element as SolidElement } from "solid-js";

export interface NativeEvent {
  type: "click" | "input" | "change";
  target: { id: number; value?: string };
  currentTarget: { id: number; value?: string };
  stopPropagation(): void;
}

export interface NativeInputEvent extends NativeEvent {
  type: "input";
  target: { id: number; value: string };
}

export interface NativeChangeEvent extends NativeEvent {
  type: "change";
  target: { id: number; value: string };
}

export type NativeLength = number | string;

export interface NativeStyle {
  display?: "block" | "flow-root" | "flex" | "grid" | "none" | "contents" | "inline-flex" | "inline" | "inline-block";
  writingMode?: "horizontal-tb" | "vertical-rl" | "vertical-lr";
  direction?: "ltr" | "rtl";
  flexDirection?: "row" | "column" | "row-reverse" | "column-reverse";
  flexWrap?: "nowrap" | "wrap" | "wrap-reverse";
  flexFlow?: string;
  flex?: number | string;
  flexGrow?: number;
  flexShrink?: number;
  flexBasis?: NativeLength;
  justifyContent?: "flex-start" | "flex-end" | "center" | "space-between" | "space-around" | "space-evenly";
  alignItems?: "stretch" | "flex-start" | "flex-end" | "center" | "baseline" | "first-baseline" | "last-baseline";
  alignSelf?: NativeStyle["alignItems"] | "auto";
  alignContent?: NativeStyle["justifyContent"] | "stretch";
  width?: NativeLength;
  height?: NativeLength;
  minWidth?: NativeLength;
  maxWidth?: NativeLength;
  minHeight?: NativeLength;
  maxHeight?: NativeLength;
  inlineSize?: NativeLength;
  blockSize?: NativeLength;
  minInlineSize?: NativeLength;
  maxInlineSize?: NativeLength;
  minBlockSize?: NativeLength;
  maxBlockSize?: NativeLength;
  aspectRatio?: number;
  order?: number;
  gap?: NativeLength;
  rowGap?: NativeLength;
  columnGap?: NativeLength;
  gridTemplateColumns?: string | Array<number | string>;
  padding?: number | string;
  paddingTop?: NativeLength;
  paddingRight?: NativeLength;
  paddingBottom?: NativeLength;
  paddingLeft?: NativeLength;
  paddingInline?: NativeLength;
  paddingBlock?: NativeLength;
  paddingInlineStart?: NativeLength;
  paddingInlineEnd?: NativeLength;
  paddingBlockStart?: NativeLength;
  paddingBlockEnd?: NativeLength;
  margin?: number | string;
  marginTop?: NativeLength;
  marginRight?: NativeLength;
  marginBottom?: NativeLength;
  marginLeft?: NativeLength;
  marginInline?: NativeLength;
  marginBlock?: NativeLength;
  marginInlineStart?: NativeLength;
  marginInlineEnd?: NativeLength;
  marginBlockStart?: NativeLength;
  marginBlockEnd?: NativeLength;
  backgroundColor?: string;
  color?: string;
  fontSize?: number | string;
  fontFamily?: string;
  fontWeight?: number | string;
  fontStyle?: "normal" | "italic" | "oblique" | string;
  language?: string;
  letterSpacing?: NativeLength;
  wordSpacing?: NativeLength;
  tabSize?: NativeLength;
  textIndent?: NativeLength;
  textTransform?: "none" | "uppercase" | "lowercase" | "capitalize";
  textOverflow?: "clip" | "ellipsis";
  textAlignLast?: "auto" | "start" | "end" | "left" | "right" | "center" | "justify";
  visibility?: "visible" | "hidden" | "collapse";
  pointerEvents?: string;
  cursor?: string;
  outline?: string;
  outlineStyle?: string;
  outlineOffset?: NativeLength;
  lineHeight?: NativeLength;
  whiteSpace?: "normal" | "nowrap" | "pre" | "pre-wrap" | "pre-line";
  textAlign?: "left" | "center" | "right" | "justify";
  borderWidth?: NativeLength;
  border?: NativeLength;
  borderColor?: string;
  borderRadius?: NativeLength;
  borderTopWidth?: NativeLength;
  borderRightWidth?: NativeLength;
  borderBottomWidth?: NativeLength;
  borderLeftWidth?: NativeLength;
  borderInlineWidth?: NativeLength;
  borderBlockWidth?: NativeLength;
  borderInlineStartWidth?: NativeLength;
  borderInlineEndWidth?: NativeLength;
  borderBlockStartWidth?: NativeLength;
  borderBlockEndWidth?: NativeLength;
  borderTopColor?: string;
  borderRightColor?: string;
  borderBottomColor?: string;
  borderLeftColor?: string;
  borderTopLeftRadius?: NativeLength;
  borderTopRightRadius?: NativeLength;
  borderBottomRightRadius?: NativeLength;
  borderBottomLeftRadius?: NativeLength;
  boxSizing?: "border-box" | "content-box";
  overflow?: "visible" | "hidden" | "clip" | "auto" | "scroll" | string;
  overflowX?: "visible" | "hidden" | "clip" | "auto" | "scroll";
  overflowY?: "visible" | "hidden" | "clip" | "auto" | "scroll";
  scrollbarGutter?: string;
  scrollbarWidth?: "auto" | "thin" | "none";
  outlineWidth?: NativeLength;
  outlineColor?: string;
  boxShadow?: string;
  position?: "static" | "relative" | "absolute" | "fixed" | "sticky";
  top?: NativeLength;
  right?: NativeLength;
  bottom?: NativeLength;
  left?: NativeLength;
  inset?: NativeLength;
  zIndex?: number;
  gridTemplateRows?: string | Array<number | string>;
  gridAutoFlow?: "row" | "column" | "row dense" | "column dense" | string;
  gridTemplateAreas?: string;
  gridColumn?: string;
  gridRow?: string;
  gridArea?: string;
  gridColumnStart?: number;
  gridColumnEnd?: number;
  gridRowStart?: number;
  gridRowEnd?: number;
  placeContent?: string;
  placeItems?: string;
  placeSelf?: string;
  justifyItems?: string;
  justifySelf?: string;
  backgroundGradient?: string;
  backgroundImage?: string;
  opacity?: number | string;
  isolation?: "auto" | "isolate";
  transform?: string;
  transformOrigin?: string;
  transition?: string;
  transitionProperty?: string;
  transitionDuration?: number | string;
  transitionTimingFunction?: string;
  transitionDelay?: number | string;
  shapeOutside?: string;
  shapeMargin?: NativeLength;
  shapeImageThreshold?: number;
  clipRule?: "nonzero" | "evenodd" | string;
  colorInterpolation?: "auto" | "sRGB" | "linearRGB" | string;
  shapeRendering?: "auto" | "optimizeSpeed" | "crispEdges" | "geometricPrecision" | string;
  textRendering?: "auto" | "optimizeSpeed" | "optimizeLegibility" | "geometricPrecision" | string;
  vectorEffect?: "none" | "non-scaling-stroke" | string;
  cx?: NativeLength;
  cy?: NativeLength;
  r?: NativeLength;
  rx?: NativeLength;
  ry?: NativeLength;
  x?: NativeLength;
  y?: NativeLength;
  fill?: string;
  stroke?: string;
  strokeWidth?: NativeLength;
  float?: "none" | "left" | "right";
  clear?: "none" | "left" | "right" | "both";
  startingStyle?: NativeStyle;
  "@starting-style"?: NativeStyle;
}

export interface NativeNode {
  readonly id: number;
  readonly type: string;
}

export interface NativeProps {
  children?: SolidElement;
  style?: NativeStyle;
  ref?: ((node: NativeNode) => void) | NativeNode;
  onClick?: (event: NativeEvent) => void;
  onInput?: (event: NativeInputEvent | NativeChangeEvent) => void;
  onChange?: (event: NativeChangeEvent) => void;
  value?: string | number;
  disabled?: boolean;
  readOnly?: boolean;
  tabIndex?: number;
  focusable?: boolean;
  selected?: boolean;
  states?: Set<string> | string[] | Record<string, boolean>;
  state?: string;
  slot?: string;
  name?: string;
}

export class CustomStateSet extends Set<string> {}

export const CSS: {
  supports(first: string, second?: string): boolean;
};

export namespace JSX {
  type Element = SolidElement;
  interface ElementChildrenAttribute { children: {}; }
  interface IntrinsicElements {
    row: NativeProps;
    column: NativeProps;
    div: NativeProps;
    label: NativeProps;
    text: NativeProps;
    button: NativeProps;
    input: NativeProps;
    grid: NativeProps;
    select: NativeProps;
    option: NativeProps;
    optgroup: NativeProps;
    slot: NativeProps;
    svg: NativeProps;
    circle: NativeProps;
    ellipse: NativeProps;
    rect: NativeProps;
    path: NativeProps;
    line: NativeProps;
    polyline: NativeProps;
    polygon: NativeProps;
    g: NativeProps;
  }
}

export function dispatchClick(id: number): void;
export function dispatchInput(id: number, value: string): void;
export function dispatchKey(id: number, key: string): void;
export function mountApp(component: Component): void;
