#import "RNPencilKit.h"
#import <UIKit/UIKit.h>  // ✅ Ensures UIImage, NSURL, NSData are available
#import <react/renderer/components/RNPencilKitSpec/ComponentDescriptors.h>
#import <react/renderer/components/RNPencilKitSpec/EventEmitters.h>
#import <react/renderer/components/RNPencilKitSpec/Props.h>
#import <react/renderer/components/RNPencilKitSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"
#import <React/RCTViewManager.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

using namespace facebook::react;

static inline const std::shared_ptr<const RNPencilKitEventEmitter>
getEmitter(const SharedViewEventEmitter emitter) {
  return std::static_pointer_cast<const RNPencilKitEventEmitter>(emitter);
}

@interface RNPencilKit () <RCTRNPencilKitViewProtocol, PKCanvasViewDelegate, PKToolPickerObserver, UIScrollViewDelegate>
// We adopt UIScrollViewDelegate to handle zoom/pan.
@end

#pragma mark - Image Helper

// Helper method to generate a solid color UIImage
@implementation RNPencilKit (ImageHelpers)

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
  if (CGSizeEqualToSize(size, CGSizeZero)) {
    size = CGSizeMake(10, 10); // Fallback size
  }
  UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
  [color setFill];
  UIRectFill(CGRectMake(0, 0, size.width, size.height));
  UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return image;
}

@end


@implementation RNPencilKit {
  UIView *_containerView;            // Container to hold background + PKCanvasView
  UIImageView *_backgroundImageView; // For showing either white or custom image
  PKCanvasView *_Nonnull _view;
  PKToolPicker *_Nullable _toolPicker;


    UIScrollView *_panZoomScrollView;  // Controls pinch-to-zoom & pan
     UIView *_zoomableContentView;      // Holds both background + strokes

  Props::Shared _props;
}


#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
  // We want the entire background + canvas to scale/pan together
  return _zoomableContentView;
}


- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const RNPencilKitProps>();
    _props = defaultProps;

    //
    //  A) The top-level container for React
    //
    _containerView = [[UIView alloc] initWithFrame:frame];
    _containerView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _containerView.clipsToBounds = YES;

    //
    //  B) Create a UIScrollView to handle pinch-zoom & panning
    //
    _panZoomScrollView = [[UIScrollView alloc] initWithFrame:_containerView.bounds];
    _panZoomScrollView.delegate = self; // For viewForZoomingInScrollView:
    _panZoomScrollView.minimumZoomScale = 1.0;
    _panZoomScrollView.maximumZoomScale = 5.0;
    _panZoomScrollView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      
    _panZoomScrollView.panGestureRecognizer.minimumNumberOfTouches = 2;
    // Add the scroll view to the container
    [_containerView addSubview:_panZoomScrollView];

    //
    //  C) Our "content" view that holds BOTH background & PKCanvasView
    //
    //     We'll return this from viewForZoomingInScrollView:
    //
    _zoomableContentView = [[UIView alloc] initWithFrame:_panZoomScrollView.bounds];
    _zoomableContentView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // By default, fill the scroll view
    [_panZoomScrollView addSubview:_zoomableContentView];
    _panZoomScrollView.contentSize = _zoomableContentView.bounds.size;

    //
    //  D) Background image inside _zoomableContentView
    //
    _backgroundImageView = [[UIImageView alloc] initWithFrame:_zoomableContentView.bounds];
    _backgroundImageView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _backgroundImageView.contentMode = UIViewContentModeScaleAspectFit;

    // Default to a white image so there’s never just black
    UIImage *defaultWhite =
      [RNPencilKit imageWithColor:[UIColor whiteColor]
                             size:_zoomableContentView.bounds.size];
    _backgroundImageView.image = defaultWhite;

    [_zoomableContentView addSubview:_backgroundImageView];

    //
    //  E) Create PKCanvasView (transparent), place it ON TOP of the background
    //
    _view = [[PKCanvasView alloc] initWithFrame:_zoomableContentView.bounds];
    _view.delegate = self; // PKCanvasViewDelegate
    _view.drawingPolicy = PKCanvasViewDrawingPolicyAnyInput;
    _view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // CRUCIAL: Disable PKCanvasView’s own scroll/pinch
    _view.scrollEnabled = NO;

    // If we want it transparent by default (over background):
    _view.opaque = NO;
    _view.backgroundColor = [UIColor clearColor];

    [_zoomableContentView addSubview:_view];

    //
    //  F) ToolPicker setup
    //
    _toolPicker = [[PKToolPicker alloc] init];
    [_toolPicker addObserver:_view];
    [_toolPicker addObserver:self];
    [_toolPicker setVisible:YES forFirstResponder:_view];

    //
    //  G) Finally, set containerView as RN content
    //
    self.contentView = _containerView;
  }
  return self;
}




- (void)dealloc {
  [_toolPicker removeObserver:_view];
  [_toolPicker removeObserver:self];
}

#pragma mark - Updating Props

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps {
  // Cast to your custom RNPencilKitProps
  auto prev = std::static_pointer_cast<const RNPencilKitProps>(_props);
  auto next = std::static_pointer_cast<const RNPencilKitProps>(props);

  // alwaysBounceVertical
  if (prev->alwaysBounceVertical ^ next->alwaysBounceVertical) {
    _view.alwaysBounceVertical = next->alwaysBounceVertical;
  }
  // alwaysBounceHorizontal
  if (prev->alwaysBounceHorizontal ^ next->alwaysBounceHorizontal) {
    _view.alwaysBounceHorizontal = next->alwaysBounceHorizontal;
  }


    // IMAGE URL LOADING - FIXED
    if (prev->imageURL != next->imageURL) {
        RCTLogInfo(@"[RNPencilKit] Attempting to set background using imageURL: %s",
                   next->imageURL.c_str());

        if (!next->imageURL.empty()) {
            std::string urlString = next->imageURL;
            NSString *nsUrlString = [NSString stringWithUTF8String:urlString.c_str()];
            NSURL *url;

            // Handle both "file://" and remote URLs
            if ([nsUrlString hasPrefix:@"file://"]) {
                RCTLogInfo(@"[RNPencilKit] Detected local file path.");
                nsUrlString = [nsUrlString stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                url = [NSURL fileURLWithPath:nsUrlString];
            } else {
                RCTLogInfo(@"[RNPencilKit] Detected remote URL.");
                url = [NSURL URLWithString:nsUrlString];
            }

            RCTLogInfo(@"[RNPencilKit] Constructed NSURL: %@", url);

            if (url) {
                // Load the image asynchronously
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    NSError *error = nil;
                    NSData *imgData = [NSData dataWithContentsOfURL:url options:0 error:&error];

                    if (error || !imgData) {
                        RCTLogInfo(@"[RNPencilKit] Failed to load image data: %@. Path: %@", error, nsUrlString);

                        // Log if the file exists (for local file system debugging)
                        if ([url isFileURL]) {
                            BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:nsUrlString];
                            RCTLogInfo(@"[RNPencilKit] File exists at path (%@): %@", nsUrlString, fileExists ? @"YES" : @"NO");
                        }

                        return;
                    }

                    UIImage *loadedImage = [UIImage imageWithData:imgData];
                    if (!loadedImage) {
                        RCTLogInfo(@"[RNPencilKit] UIImage is nil after decoding data.");
                        return;
                    }

                    // Ensure UI updates happen on the main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        RCTLogInfo(@"[RNPencilKit] Successfully loaded UIImage. Setting background now.");

                        _backgroundImageView.image = loadedImage;
                        _backgroundImageView.hidden = NO;
                        _backgroundImageView.alpha = 1.0;

                        // Force layout update to ensure image is visible
                        [_backgroundImageView setNeedsLayout];
                        [_backgroundImageView layoutIfNeeded];

                        // Debugging: Print the actual frame size of the image view
                        RCTLogInfo(@"[RNPencilKit] Background Image View Size: Width = %f, Height = %f",
                                   _backgroundImageView.bounds.size.width, _backgroundImageView.bounds.size.height);
                    });
                });
            } else {
                RCTLogInfo(@"[RNPencilKit] Invalid NSURL generated.");
            }
        } else {
            // Reset to default background if imageURL is empty
            RCTLogInfo(@"[RNPencilKit] Received empty imageURL. Resetting to white background.");

            UIImage *whiteImage = [RNPencilKit imageWithColor:[UIColor whiteColor]
                                                        size:_backgroundImageView.bounds.size];
            dispatch_async(dispatch_get_main_queue(), ^{
                _backgroundImageView.image = whiteImage;
                _backgroundImageView.hidden = NO;
                _backgroundImageView.alpha = 1.0;
                [_backgroundImageView setNeedsLayout];
                [_backgroundImageView layoutIfNeeded];
            });
        }
    }






  // drawingPolicy
  if (prev->drawingPolicy != next->drawingPolicy) {
    _view.drawingPolicy =
    (next->drawingPolicy == RNPencilKitDrawingPolicy::Anyinput
     ? PKCanvasViewDrawingPolicyAnyInput
     : next->drawingPolicy == RNPencilKitDrawingPolicy::Default
       ? PKCanvasViewDrawingPolicyDefault
       : PKCanvasViewDrawingPolicyPencilOnly);
  }

  // Ruler
  if (prev->isRulerActive ^ next->isRulerActive) {
    [_view setRulerActive:next->isRulerActive];
  }

  // Opacity
    if (prev->isOpaque ^ next->isOpaque) {
       _view.opaque = next->isOpaque;
       if (!next->isOpaque) {
         // Make canvas truly transparent
         _view.backgroundColor = [UIColor clearColor];
       }
     }

  // Background color
  if (prev->backgroundColor ^ next->backgroundColor) {
    [_view setBackgroundColor:intToColor(next->backgroundColor)];
  }

  _props = next; // properly cast above
  [super updateProps:props oldProps:oldProps];
}

#pragma mark - Public Methods

- (void)clear {
  [_view setDrawing:[[PKDrawing alloc] init]];
}

- (void)showToolPicker {
  [_view becomeFirstResponder];
}

- (void)hideToolPicker {
  [_view resignFirstResponder];
}

- (void)redo {
  [_view.undoManager redo];
}

- (void)undo {
  [_view.undoManager undo];
}

- (NSString *)getBase64Data {
  return [_view.drawing.dataRepresentation base64EncodedStringWithOptions:0];
}

- (NSString *)getBase64PngData:(double)scale {
  NSData *data = _view.drawing.dataRepresentation;
  if (!data) {
    return nil;
  }
  UIImage *image = [_view.drawing imageFromRect:_view.bounds
                                          scale:(scale == 0 ? UIScreen.mainScreen.scale : scale)];
  NSData *imageData = UIImagePNGRepresentation(image);
  return [imageData base64EncodedStringWithOptions:0];
}

- (NSString *)getBase64JpegData:(double)scale compression:(double)compression {
  NSData *data = _view.drawing.dataRepresentation;
  if (!data) {
    return nil;
  }
  UIImage *image = [_view.drawing imageFromRect:_view.bounds
                                          scale:(scale == 0 ? UIScreen.mainScreen.scale : scale)];
  NSData *imageData = UIImageJPEGRepresentation(image, (compression == 0 ? 0.93 : compression));
  return [imageData base64EncodedStringWithOptions:0];
}

- (NSString *)saveDrawing:(NSString *)path {
  NSData *data = [_view.drawing dataRepresentation];
  if (!data) {
    return nil;
  }
  NSError *error = nil;
  [data writeToURL:[NSURL fileURLWithPath:path]
           options:NSDataWritingAtomic
             error:&error];
  if (error) {
    return nil;
  }
  return [data base64EncodedStringWithOptions:0];
}

- (BOOL)loadDrawing:(NSString *)path {
  NSURL *url = [NSURL fileURLWithPath:path];
  if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
    return NO;
  }
  NSData *data = [NSData dataWithContentsOfURL:url];
  return [self loadWithData:data];
}

- (BOOL)loadBase64Data:(NSString *)base64 {
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64
                                                     options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (!data) {
    return NO;
  }
  NSError *error = nil;
  PKDrawing *drawing = [[PKDrawing alloc] initWithData:data error:&error];
  if (error || !drawing) {
    return NO;
  }

  // Scale if bigger than the canvas
  CGRect drawingBounds = drawing.bounds;
  if (!CGRectIsEmpty(drawingBounds)) {
    CGSize targetSize = _view.bounds.size;
    if (targetSize.width > 0 && targetSize.height > 0) {
      BOOL alreadyScaled = (CGRectGetWidth(drawingBounds) <= targetSize.width &&
                            CGRectGetHeight(drawingBounds) <= targetSize.height);
      if (!alreadyScaled) {
        CGFloat scaleX = targetSize.width / CGRectGetWidth(drawingBounds);
        CGFloat scaleY = targetSize.height / CGRectGetHeight(drawingBounds);
        CGFloat scale = MIN(scaleX, scaleY);

        CGFloat offsetX = (targetSize.width - (drawingBounds.size.width * scale)) / 2
                          - (drawingBounds.origin.x * scale);
        CGFloat offsetY = (targetSize.height - (drawingBounds.size.height * scale)) / 2
                          - (drawingBounds.origin.y * scale);

        CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
        transform = CGAffineTransformTranslate(transform, offsetX / scale, offsetY / scale);

        PKDrawing *transformedDrawing = [drawing drawingByApplyingTransform:transform];
        drawing = transformedDrawing;
      }
    }
  }
  [_view setDrawing:drawing];
  return YES;
}

- (BOOL)loadWithData:(NSData *)data {
  if (!data) {
    return NO;
  }
  NSError *error = nil;
  PKDrawing *drawing = [[PKDrawing alloc] initWithData:data error:&error];
  if (error || !drawing) {
    return NO;
  }

  PKCanvasView *newCanvas = [self copyCanvas:_view];
  [_view removeFromSuperview];
  _view = newCanvas;

  // Re-add the new canvas above the background
  [_containerView addSubview:_view];
  [_view.undoManager removeAllActions];
  [_view setDrawing:drawing];
  return YES;
}

- (PKCanvasView *)copyCanvas:(PKCanvasView *)v {
  PKCanvasView *newView = [[PKCanvasView alloc] initWithFrame:v.frame];
  newView.alwaysBounceVertical   = v.alwaysBounceVertical;
  newView.alwaysBounceHorizontal = v.alwaysBounceHorizontal;
  [newView setRulerActive:v.isRulerActive];
  [newView setBackgroundColor:v.backgroundColor];
  [newView setDrawingPolicy:v.drawingPolicy];
  [newView setOpaque:v.isOpaque];
  newView.delegate = self;

  [_toolPicker removeObserver:v];
  [_toolPicker addObserver:newView];
  [_toolPicker setVisible:true forFirstResponder:newView];
  if (_toolPicker.isVisible) {
    [newView becomeFirstResponder];
  }

  // Copy zoom/pan
  newView.minimumZoomScale = v.minimumZoomScale;
  newView.maximumZoomScale = v.maximumZoomScale;
  newView.zoomScale = v.zoomScale;
  newView.delegate = self;
  return newView;
}

- (void)setTool:(NSString *)toolType width:(double)width color:(NSInteger)color {
  std::string tool = [toolType UTF8String];
  BOOL isWidthValid = (width != 0);
  BOOL isColorValid = (color != 0);
  double defaultWidth = 1.0;
  UIColor *defaultColor = [UIColor blackColor];

  if (tool == "pen") {
    _toolPicker.selectedTool = _view.tool =
    [[PKInkingTool alloc] initWithInkType:PKInkTypePen
                                    color:(isColorValid ? intToColor(color) : defaultColor)
                                    width:(isWidthValid ? width : defaultWidth)];
  }
  if (tool == "pencil") {
    _toolPicker.selectedTool = _view.tool =
    [[PKInkingTool alloc] initWithInkType:PKInkTypePencil
                                    color:(isColorValid ? intToColor(color) : defaultColor)
                                    width:(isWidthValid ? width : defaultWidth)];
  }
  if (tool == "marker") {
    _toolPicker.selectedTool = _view.tool =
    [[PKInkingTool alloc] initWithInkType:PKInkTypeMarker
                                    color:(isColorValid ? intToColor(color) : defaultColor)
                                    width:(isWidthValid ? width : defaultWidth)];
  }

  // iOS 17 extra tools
  if (@available(iOS 17.0, *)) {
    if (tool == "monoline") {
      _toolPicker.selectedTool = _view.tool =
      [[PKInkingTool alloc] initWithInkType:PKInkTypeMonoline
                                      color:(isColorValid ? intToColor(color) : defaultColor)
                                      width:(isWidthValid ? width : defaultWidth)];
    }
    if (tool == "fountainPen") {
      _toolPicker.selectedTool = _view.tool =
      [[PKInkingTool alloc] initWithInkType:PKInkTypeFountainPen
                                      color:(isColorValid ? intToColor(color) : defaultColor)
                                      width:(isWidthValid ? width : defaultWidth)];
    }
    if (tool == "watercolor") {
      _toolPicker.selectedTool = _view.tool =
      [[PKInkingTool alloc] initWithInkType:PKInkTypeWatercolor
                                      color:(isColorValid ? intToColor(color) : defaultColor)
                                      width:(isWidthValid ? width : defaultWidth)];
    }
    if (tool == "crayon") {
      _toolPicker.selectedTool = _view.tool =
      [[PKInkingTool alloc] initWithInkType:PKInkTypeCrayon
                                      color:(isColorValid ? intToColor(color) : defaultColor)
                                      width:(isWidthValid ? width : defaultWidth)];
    }
  }

  // Erasers
  if (tool == "eraserVector") {
    if (@available(iOS 16.4, *)) {
      _toolPicker.selectedTool = _view.tool =
      [[PKEraserTool alloc] initWithEraserType:PKEraserTypeVector
                                         width:(isWidthValid ? width : defaultWidth)];
    } else {
      _toolPicker.selectedTool = _view.tool =
      [[PKEraserTool alloc] initWithEraserType:PKEraserTypeVector];
    }
  }
  if (tool == "eraserBitmap") {
    if (@available(iOS 16.4, *)) {
      _toolPicker.selectedTool = _view.tool =
      [[PKEraserTool alloc] initWithEraserType:PKEraserTypeBitmap
                                         width:(isWidthValid ? width : defaultWidth)];
    } else {
      _toolPicker.selectedTool = _view.tool =
      [[PKEraserTool alloc] initWithEraserType:PKEraserTypeBitmap];
    }
  }
  if (@available(iOS 16.4, *)) {
    if (tool == "eraserFixedWidthBitmap") {
      _toolPicker.selectedTool = _view.tool =
      [[PKEraserTool alloc] initWithEraserType:PKEraserTypeFixedWidthBitmap
                                         width:(isWidthValid ? width : defaultWidth)];
    }
  }
}

@end

#pragma mark - PKCanvasViewDelegate

@implementation RNPencilKit (PKCanvasviewDelegate)

- (void)canvasViewDidBeginUsingTool:(PKCanvasView *)canvasView {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onCanvasViewDidBeginUsingTool({});
  }
}

- (void)canvasViewDrawingDidChange:(PKCanvasView *)canvasView {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onCanvasViewDrawingDidChange({});
  }
}

- (void)canvasViewDidEndUsingTool:(PKCanvasView *)canvasView {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onCanvasViewDidEndUsingTool({});
  }
}

- (void)canvasViewDidFinishRendering:(PKCanvasView *)canvasView {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onCanvasViewDidFinishRendering({});
  }
}

@end

#pragma mark - PKToolPickerObserver

@implementation RNPencilKit (PKToolPickerObserver)

- (void)toolPickerVisibilityDidChange:(PKToolPicker *)toolPicker {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onToolPickerVisibilityDidChange({});
  }
}

- (void)toolPickerSelectedToolDidChange:(PKToolPicker *)toolPicker {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onToolPickerSelectedToolDidChange({});
  }
}

- (void)toolPickerFramesObscuredDidChange:(PKToolPicker *)toolPicker {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onToolPickerFramesObscuredDidChange({});
  }
}

- (void)toolPickerIsRulerActiveDidChange:(PKToolPicker *)toolPicker {
  if (auto e = getEmitter(_eventEmitter)) {
    e->onToolPickerIsRulerActiveDidChange({});
  }
}

@end

#pragma mark - React Native / Component Descriptor

@implementation RNPencilKit (ReactNative)

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args {
  RCTRNPencilKitHandleCommand(self, commandName, args);
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<RNPencilKitComponentDescriptor>();
}

Class<RCTComponentViewProtocol> RNPencilKitCls(void) {
  return RNPencilKit.class;
}

@end
