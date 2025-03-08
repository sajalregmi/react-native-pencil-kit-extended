// file: PencilKit.ios.tsx

import { type ForwardedRef, forwardRef, useImperativeHandle, useRef } from 'react';
import { findNodeHandle, processColor, Text } from 'react-native';
import {
  type PencilKitProps,
  type PencilKitRef,
  PencilKitUtil,
} from 'react-native-pencil-kit';
import NativeRNPencilKitUtil from '../spec/NativeRNPencilKitUtil';
import NativePencilKitView, { Commands } from '../spec/RNPencilKitNativeComponent';

function PencilKitComponent(
  {
    alwaysBounceHorizontal = true,
    alwaysBounceVertical = true,
    isRulerActive = false,
    drawingPolicy = 'default',
    backgroundColor,
    isOpaque = true,
    imageURL, // optional string – pass it into the native side
    onToolPickerFramesObscuredDidChange,
    onToolPickerIsRulerActiveDidChange,
    onToolPickerSelectedToolDidChange,
    onToolPickerVisibilityDidChange,
    onCanvasViewDidBeginUsingTool,
    onCanvasViewDidEndUsingTool,
    onCanvasViewDidFinishRendering,
    onCanvasViewDrawingDidChange,
    ...rest
  }: PencilKitProps,
  ref: ForwardedRef<PencilKitRef>,
) {
  const nativeRef = useRef(null);

  useImperativeHandle(
    ref,
    () => ({
      clear: () => Commands.clear(nativeRef.current!),
      showToolPicker: () => Commands.showToolPicker(nativeRef.current!),
      hideToolPicker: () => Commands.hideToolPicker(nativeRef.current!),
      redo: () => Commands.redo(nativeRef.current!),
      undo: () => Commands.undo(nativeRef.current!),
      loadStroke: (strokeBase64) => Commands.loadStroke(nativeRef.current!, strokeBase64),

      applyStrokeDiff: (addedStrokes: string[], removedStrokes: string[]) =>
        Commands.applyStrokeDiff(nativeRef.current!, addedStrokes, removedStrokes),

      saveDrawing: async (path) => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.saveDrawing(handle, path);
      },
      loadDrawing: async (path) => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.loadDrawing(handle, path);
      },
      getBase64Data: async () => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.getBase64Data(handle);
      },
      getBase64PngData: async ({scale = 0} = {scale: 0}) => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.getBase64PngData(handle, scale).then(
          d => `data:image/png;base64,${d}`,
        );
      },
      getBase64JpegData: async ({scale = 0, compression = 0} = {scale: 0, compression: 0}) => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.getBase64JpegData(handle, scale, compression).then(
          d => `data:image/jpeg;base64,${d}`,
        );
      },
      loadBase64Data: async base64 => {
        const handle = findNodeHandle(nativeRef.current) ?? -1;
        return NativeRNPencilKitUtil.loadBase64Data(handle, base64);
      },
      setTool: ({color, toolType, width}) =>
        Commands.setTool(
          nativeRef.current!,
          toolType,
          width ?? 0,
          color ? (processColor(color) as number) : 0,
        ),
    }),
    [],
  );

  if (!PencilKitUtil.isPencilKitAvailable()) {
    return (
      <Text>{"This iOS version doesn't support PencilKit. iOS 14+ required."}</Text>
    );
  }

  return (
    <NativePencilKitView
      ref={nativeRef}
      alwaysBounceHorizontal={alwaysBounceHorizontal}
      alwaysBounceVertical={alwaysBounceVertical}
      isRulerActive={isRulerActive}
      drawingPolicy={drawingPolicy}
      backgroundColor={processColor(backgroundColor) as number}
      isOpaque={isOpaque}
      imageURL= {imageURL}
      onToolPickerFramesObscuredDidChange={onToolPickerFramesObscuredDidChange}
      onToolPickerIsRulerActiveDidChange={onToolPickerIsRulerActiveDidChange}
      onToolPickerSelectedToolDidChange={onToolPickerSelectedToolDidChange}
      onToolPickerVisibilityDidChange={onToolPickerVisibilityDidChange}
      onCanvasViewDidBeginUsingTool={onCanvasViewDidBeginUsingTool}
      onCanvasViewDidEndUsingTool={onCanvasViewDidEndUsingTool}
      onCanvasViewDidFinishRendering={onCanvasViewDidFinishRendering}
      onCanvasViewDrawingDidChange={onCanvasViewDrawingDidChange}
      {...rest}
    />
  );
}

export const PencilKit = forwardRef(PencilKitComponent);
