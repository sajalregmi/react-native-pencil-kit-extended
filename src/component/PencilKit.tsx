import { type ForwardedRef, forwardRef } from 'react';
import { type ColorValue, Text, type ViewProps } from 'react-native';
import type { DirectEventHandler, WithDefault } from 'react-native/Libraries/Types/CodegenTypes';
import { CanvasViewDrawingDidChangeEvent } from '../spec/RNPencilKitNativeComponent';

export type PencilKitProps = {
  alwaysBounceVertical?: boolean;
  alwaysBounceHorizontal?: boolean;
  isRulerActive?: boolean;
  backgroundColor?: ColorValue;
  drawingPolicy?: WithDefault<'default' | 'anyinput' | 'pencilonly', 'default'>;
  isOpaque?: boolean;
  imageURL?: string;

  onToolPickerVisibilityDidChange?: DirectEventHandler<{}>;
  onToolPickerIsRulerActiveDidChange?: DirectEventHandler<{}>;
  onToolPickerFramesObscuredDidChange?: DirectEventHandler<{}>;
  onToolPickerSelectedToolDidChange?: DirectEventHandler<{}>;
  onCanvasViewDidBeginUsingTool?: DirectEventHandler<{}>;
  onCanvasViewDidEndUsingTool?: DirectEventHandler<{}>;
  onCanvasViewDrawingDidChange?: DirectEventHandler<CanvasViewDrawingDidChangeEvent>;
  onCanvasViewDidFinishRendering?: DirectEventHandler<{}>;
} & ViewProps;
export type PencilKitTool =
  | 'pen'
  | 'pencil'
  | 'marker'
  | 'monoline'
  | 'fountainPen'
  | 'watercolor'
  | 'crayon'
  | 'eraserVector'
  | 'eraserBitmap'
  | 'eraserFixedWidthBitmap';
export type PencilKitRef = {
  clear: () => void;
  showToolPicker: () => void;
  hideToolPicker: () => void;
  redo: () => void;
  undo: () => void;
  loadStroke: (strokeBase64: string) => void;
  setTool: (params: { toolType: PencilKitTool; width?: number; color?: ColorValue }) => void;
  saveDrawing: (path: string) => Promise<string>;
  loadDrawing: (path: string) => Promise<void>;
  getBase64Data: () => Promise<string>;
  getBase64PngData: (params?: { scale?: number }) => Promise<string>;
  getBase64JpegData: (params?: { scale?: number; compression?: number }) => Promise<string>;
  loadBase64Data: (base64: string) => Promise<void>;

};
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const PencilKit = forwardRef((props: PencilKitProps, ref: ForwardedRef<PencilKitRef>) => {
  return <Text>{"This platform doesn't support pencilkit"}</Text>;
});
