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
  quotes?: "auto" | "none" | string;
  clipPath?: string;
  visibility?: "visible" | "hidden" | "collapse";
  pointerEvents?: "auto" | "none" | "visiblePainted" | "visibleFill" | "visibleStroke" | "visible" | "painted" | "fill" | "stroke" | "all" | string;
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
  ":read-only"?: NativeStyle;
  ":read-write"?: NativeStyle;
  ":popover-open"?: NativeStyle;
  "::backdrop"?: NativeStyle;
  [mediaOrSelector: `@media ${string}`]: NativeStyle | undefined;
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
  readonly?: boolean;
  contentEditable?: boolean | "true" | "false";
  contenteditable?: boolean | "true" | "false";
  popover?: "auto" | "manual" | "hint" | boolean | string;
  popoverTarget?: string;
  popovertarget?: string;
  popoverTargetAction?: "toggle" | "show" | "hide";
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
    q: NativeProps;
  }
}

export function dispatchClick(id: number): void;
export function dispatchInput(id: number, value: string): void;
export function dispatchKey(id: number, key: string): void;
export function mountApp(component: Component): void;
export function matchMedia(query: string): { matches: boolean; media: string };
export function getPreferences(): { colorScheme: "light" | "dark"; contrast: string; reducedMotion: string };
export function setPreferences(prefs: Partial<{ colorScheme: "light" | "dark"; contrast: string; reducedMotion: string }>): void;
export function showPopover(node: any): void;
export function hidePopover(node: any): void;
export function togglePopover(node: any, force?: boolean): void;
export function isPopoverOpen(node: any): boolean;
export function isReadOnly(node: any): boolean;
export function isReadWrite(node: any): boolean;
export function resolveQuotes(quotes?: string, lang?: string, depth?: number): { open: string; close: string } | null;
