import type { Component, Element as SolidElement } from "solid-js";

export interface NativeEvent {
  type: "click" | "input";
  target: { id: number; value?: string };
  currentTarget: { id: number; value?: string };
  stopPropagation(): void;
}

export interface NativeInputEvent extends NativeEvent {
  type: "input";
  target: { id: number; value: string };
}

export interface NativeStyle {
  display?: "block" | "inline-block" | "flex" | "grid";
  flexDirection?: "row" | "column" | "row-reverse" | "column-reverse";
  flexWrap?: "nowrap" | "wrap" | "wrap-reverse";
  flex?: number | string;
  flexGrow?: number;
  flexShrink?: number;
  flexBasis?: number | "auto" | "content";
  justifyContent?: "flex-start" | "flex-end" | "center" | "space-between" | "space-around" | "space-evenly";
  alignItems?: "stretch" | "flex-start" | "flex-end" | "center" | "baseline";
  alignSelf?: NativeStyle["alignItems"] | "auto";
  alignContent?: NativeStyle["justifyContent"] | "stretch";
  width?: number;
  height?: number;
  minWidth?: number;
  maxWidth?: number;
  minHeight?: number;
  maxHeight?: number;
  aspectRatio?: number;
  order?: number;
  gap?: number;
  gridTemplateColumns?: string | Array<number | string>;
  padding?: number | string;
  paddingTop?: number;
  paddingRight?: number;
  paddingBottom?: number;
  paddingLeft?: number;
  margin?: number | string;
  marginTop?: number | "auto";
  marginRight?: number | "auto";
  marginBottom?: number | "auto";
  marginLeft?: number | "auto";
  backgroundColor?: string;
  color?: string;
  fontSize?: number;
  borderWidth?: number;
  borderColor?: string;
  borderRadius?: number;
  borderTopWidth?: number;
  borderRightWidth?: number;
  borderBottomWidth?: number;
  borderLeftWidth?: number;
  borderTopColor?: string;
  borderRightColor?: string;
  borderBottomColor?: string;
  borderLeftColor?: string;
  borderTopLeftRadius?: number;
  borderTopRightRadius?: number;
  borderBottomRightRadius?: number;
  borderBottomLeftRadius?: number;
  boxSizing?: "border-box" | "content-box";
  overflow?: "visible" | "hidden" | "clip" | "auto" | "scroll";
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
  onInput?: (event: NativeInputEvent) => void;
  value?: string;
  disabled?: boolean;
  readOnly?: boolean;
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
  }
}

export function mountApp(component: Component): void;
