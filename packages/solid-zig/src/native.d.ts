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
  fontSize?: number;
  lineHeight?: NativeLength;
  whiteSpace?: "normal" | "nowrap" | "pre" | "pre-wrap" | "pre-line";
  textAlign?: "left" | "center" | "right" | "justify";
  borderWidth?: NativeLength;
  border?: NativeLength;
  borderColor?: string;
  borderRadius?: number;
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
  borderTopLeftRadius?: number;
  borderTopRightRadius?: number;
  borderBottomRightRadius?: number;
  borderBottomLeftRadius?: number;
  boxSizing?: "border-box" | "content-box";
  overflow?: "visible" | "hidden" | "clip" | "auto" | "scroll" | string;
  overflowX?: "visible" | "hidden" | "clip" | "auto" | "scroll";
  overflowY?: "visible" | "hidden" | "clip" | "auto" | "scroll";
  scrollbarGutter?: string;
  scrollbarWidth?: "auto" | "thin" | "none";
  outlineWidth?: number;
  outlineColor?: string;
  boxShadow?: string;
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
}

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
  }
}

export function dispatchClick(id: number): void;
export function dispatchInput(id: number, value: string): void;
export function dispatchKey(id: number, key: string): void;
export function mountApp(component: Component): void;
