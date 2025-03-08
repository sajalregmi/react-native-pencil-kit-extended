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
@property (nonatomic, assign) BOOL isProgrammaticUpdate;
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

  PKDrawing *_previousDrawing;

}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
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

    _previousDrawing = [[PKDrawing alloc] init];

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
 // [_view.undoManager removeAllActions];
    _previousDrawing = _view.drawing; // FIX: update previous drawing
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
  RCTLogInfo(@"[RNPencilKit] getBase64Data: Converting from device→doc before returning base64.");

  // 1) Grab the current device-based drawing
  PKDrawing *deviceDrawing = _view.drawing;
  if (!deviceDrawing) {
    return nil;
  }

  // 2) Build the doc→device transform, then invert to get device→doc
  CGSize viewSize = _view.bounds.size;

  // Compute the doc→device transform:
  CGFloat hRatio = viewSize.width  / kDocWidth;
  CGFloat vRatio = viewSize.height / kDocHeight;
  CGFloat scale  = MIN(hRatio, vRatio);

  // Centering offsets
  CGFloat scaledW = kDocWidth  * scale;
  CGFloat scaledH = kDocHeight * scale;
  CGFloat offsetX = (viewSize.width  - scaledW) / 2.0;
  CGFloat offsetY = (viewSize.height - scaledH) / 2.0;

  CGAffineTransform docToDevice = CGAffineTransformMakeTranslation(offsetX, offsetY);
  docToDevice = CGAffineTransformScale(docToDevice, scale, scale);

  // Invert it to get device→doc
  CGAffineTransform deviceToDoc = CGAffineTransformInvert(docToDevice);

  // 3) Convert the drawing to doc coords
  PKDrawing *docDrawing = [deviceDrawing drawingByApplyingTransform:deviceToDoc];
  CGRect docBounds = docDrawing.bounds;
  RCTLogInfo(@"[RNPencilKit] getBase64Data: docDrawing bounds = %@ (in doc coords)",
             NSStringFromCGRect(docBounds));

  // 4) Return base64 of the doc coords
  NSData *data = [docDrawing dataRepresentation];
  return [data base64EncodedStringWithOptions:0];
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


#pragma mark - Document ↔ Device Transform Helpers

static const CGFloat kDocWidth  = 1131.0;
static const CGFloat kDocHeight = 1600.0;

// Returns the transform that converts coordinates from document space (1131×1600)
// to device (canvas) space. This does an aspect-fit of the document into _view.bounds.
- (CGAffineTransform)documentToDeviceTransform {
  CGSize docSize = CGSizeMake(kDocWidth, kDocHeight);
  CGSize viewSize = _view.bounds.size;
  
  // Calculate aspect-fit scale factors.
  CGFloat hRatio = viewSize.width / docSize.width;
  CGFloat vRatio = viewSize.height / docSize.height;
  CGFloat scale  = MIN(hRatio, vRatio);
  
  // Center the document in the canvas.
  CGFloat scaledWidth  = docSize.width * scale;
  CGFloat scaledHeight = docSize.height * scale;
  CGFloat offsetX = (viewSize.width - scaledWidth) / 2.0;
  CGFloat offsetY = (viewSize.height - scaledHeight) / 2.0;
  
  // Build the transform: first translate, then scale.
  CGAffineTransform t = CGAffineTransformMakeTranslation(offsetX, offsetY);
  t = CGAffineTransformScale(t, scale, scale);
  
  RCTLogInfo(@"[RNPencilKit] documentToDeviceTransform: scale = %f, offsetX = %f, offsetY = %f", scale, offsetX, offsetY);
  return t;
}

// Returns the inverse transform: device → document coordinates.
- (CGAffineTransform)deviceToDocumentTransform {
  CGAffineTransform forward = [self documentToDeviceTransform];
  CGAffineTransform inverse = CGAffineTransformInvert(forward);
  RCTLogInfo(@"[RNPencilKit] deviceToDocumentTransform: computed inverse transform");
  return inverse;
}

// Convenience method to apply a given CGAffineTransform to a PKDrawing.
- (PKDrawing *)applyTransform:(CGAffineTransform)transform toDrawing:(PKDrawing *)drawing {
  if (!drawing) return nil;
  return [drawing drawingByApplyingTransform:transform];
}

#pragma mark - Loading Full Drawing (loadBase64Data:)

- (BOOL)loadBase64Data:(NSString *)base64 {
  RCTLogInfo(@"[RNPencilKit] loadBase64Data: Called. Interpreting base64 as doc coords.");
  self.isProgrammaticUpdate = YES;

  // 1) Decode
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64
                                                     options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (!data) {
    RCTLogError(@"[RNPencilKit] loadBase64Data: Could not decode base64 data!");
    self.isProgrammaticUpdate = NO;
    return NO;
  }

  // 2) Initialize doc-based PKDrawing
  NSError *error = nil;
  PKDrawing *docDrawing = [[PKDrawing alloc] initWithData:data error:&error];
  if (error || !docDrawing) {
    RCTLogError(@"[RNPencilKit] loadBase64Data: Could not init PKDrawing from data. Error: %@", error);
    self.isProgrammaticUpdate = NO;
    return NO;
  }

  RCTLogInfo(@"[RNPencilKit] loadBase64Data: docDrawing bounds (doc coords) = %@",
             NSStringFromCGRect(docDrawing.bounds));

  // 3) Build doc→device transform
  CGSize viewSize = _view.bounds.size;
  CGFloat hRatio = viewSize.width  / kDocWidth;
  CGFloat vRatio = viewSize.height / kDocHeight;
  CGFloat scale  = MIN(hRatio, vRatio);

  CGFloat scaledW = kDocWidth  * scale;
  CGFloat scaledH = kDocHeight * scale;
  CGFloat offsetX = (viewSize.width  - scaledW) / 2.0;
  CGFloat offsetY = (viewSize.height - scaledH) / 2.0;

  CGAffineTransform docToDevice = CGAffineTransformMakeTranslation(offsetX, offsetY);
  docToDevice = CGAffineTransformScale(docToDevice, scale, scale);

  // 4) Transform docDrawing → device coords
  PKDrawing *deviceDrawing = [docDrawing drawingByApplyingTransform:docToDevice];
  RCTLogInfo(@"[RNPencilKit] loadBase64Data: deviceDrawing bounds = %@",
             NSStringFromCGRect(deviceDrawing.bounds));

  // 5) Apply on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    [_view setDrawing:deviceDrawing];
    [_view.undoManager removeAllActions];
    _previousDrawing = deviceDrawing;

    RCTLogInfo(@"[RNPencilKit] loadBase64Data: Successfully applied drawing.");
    self.isProgrammaticUpdate = NO;
  });

  return YES;
}


#pragma mark - Loading a Single Stroke (loadBase64Stroke:)

- (BOOL)loadBase64Stroke:(NSString *)base64 {
  RCTLogInfo(@"[RNPencilKit] loadBase64Stroke: Called. Interpreting base64 as doc coords.");
  self.isProgrammaticUpdate = YES;

  // 1) Decode
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64
                                                     options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (!data) {
    RCTLogError(@"[RNPencilKit] loadBase64Stroke: Failed to decode base64 data!");
    self.isProgrammaticUpdate = NO;
    return NO;
  }

  // 2) Build a doc-based PKDrawing
  NSError *error = nil;
  PKDrawing *docDrawing = [[PKDrawing alloc] initWithData:data error:&error];
  if (error || !docDrawing || docDrawing.strokes.count == 0) {
    RCTLogError(@"[RNPencilKit] loadBase64Stroke: No valid stroke in base64 data!");
    self.isProgrammaticUpdate = NO;
    return NO;
  }

  RCTLogInfo(@"[RNPencilKit] loadBase64Stroke: docDrawing bounds (doc coords) = %@",
             NSStringFromCGRect(docDrawing.bounds));

  // 3) doc→device
  CGSize viewSize = _view.bounds.size;
  CGFloat hRatio = viewSize.width  / kDocWidth;
  CGFloat vRatio = viewSize.height / kDocHeight;
  CGFloat scale  = MIN(hRatio, vRatio);

  CGFloat scaledW = kDocWidth  * scale;
  CGFloat scaledH = kDocHeight * scale;
  CGFloat offsetX = (viewSize.width  - scaledW) / 2.0;
  CGFloat offsetY = (viewSize.height - scaledH) / 2.0;

  CGAffineTransform docToDevice = CGAffineTransformMakeTranslation(offsetX, offsetY);
  docToDevice = CGAffineTransformScale(docToDevice, scale, scale);

  PKDrawing *deviceStrokeDrawing = [docDrawing drawingByApplyingTransform:docToDevice];
  RCTLogInfo(@"[RNPencilKit] loadBase64Stroke: deviceStroke bounds = %@",
             NSStringFromCGRect(deviceStrokeDrawing.bounds));

  // 4) Merge with current drawing
  PKDrawing *currentDrawing = _view.drawing;
  PKDrawing *merged = [currentDrawing drawingByAppendingDrawing:deviceStrokeDrawing];

  // 5) Update
  dispatch_async(dispatch_get_main_queue(), ^{
    [_view setDrawing:merged];
  //  [_view.undoManager removeAllActions];
    _previousDrawing = merged;

    RCTLogInfo(@"[RNPencilKit] loadBase64Stroke: Stroke successfully applied.");
    self.isProgrammaticUpdate = NO;
  });

  return YES;
}



// Helper method to create a string representation for a stroke.
- (NSString *)loggableDescriptionForStroke:(PKStroke *)stroke {
  NSMutableString *description = [NSMutableString string];
  [description appendFormat:@"Stroke details - Ink: %@, Transform: %@", stroke.ink, NSStringFromCGAffineTransform(stroke.transform)];
  if (stroke.path) {
    [description appendFormat:@", Point count: %lu", (unsigned long)stroke.path.count];
  }
  return description;
}

- (BOOL)stroke:(PKStroke *)stroke1 isEqualToStroke:(PKStroke *)stroke2 {
    RCTLogInfo(@"[RNPencilKit] Comparing strokes using custom function.");
    
    PKInk *ink1 = stroke1.ink;
       PKInk *ink2 = stroke2.ink;
    
    // Log ink details for debugging
    RCTLogInfo(@"[RNPencilKit] Ink1: type=%@, color=%@", ink1.inkType, ink1.color);
    RCTLogInfo(@"[RNPencilKit] Ink2: type=%@, color=%@", ink2.inkType, ink2.color);
    
    // 2) Compare inkType first (pen vs pencil vs marker)
    if (![ink1.inkType isEqualToString:ink2.inkType]) {
        RCTLogInfo(@"[RNPencilKit] Ink types differ: %@ vs %@", ink1.inkType, ink2.inkType);
        return NO;
    }
    
    // 3) Compare color components with tolerance
    CGFloat r1, g1, b1, a1;
    CGFloat r2, g2, b2, a2;
    [ink1.color getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [ink2.color getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    
    RCTLogInfo(@"[RNPencilKit] Ink1 RGBA=(%.3f, %.3f, %.3f, %.3f), Ink2 RGBA=(%.3f, %.3f, %.3f, %.3f)",
               r1, g1, b1, a1, r2, g2, b2, a2);
    
    static CGFloat colorTolerance = 0.002; // Allow small floating-point differences
    if (fabs(r1 - r2) > colorTolerance ||
        fabs(g1 - g2) > colorTolerance ||
        fabs(b1 - b2) > colorTolerance ||
        fabs(a1 - a2) > colorTolerance) {
        RCTLogInfo(@"[RNPencilKit] Ink colors differ beyond tolerance.");
        return NO;
    }
    
    
    RCTLogInfo(@"[RNPencilKit] Inks are equal.");
    
    // Compare paths by count (you could extend this to compare each control point with tolerance).
    if (stroke1.path.count != stroke2.path.count) {
        RCTLogInfo(@"[RNPencilKit] Path counts differ: %lu vs %lu", (unsigned long)stroke1.path.count, (unsigned long)stroke2.path.count);
        return NO;
    }
    RCTLogInfo(@"[RNPencilKit] Path counts are equal (%lu points).", (unsigned long)stroke1.path.count);
    
    // Compare randomSeed.
    if (stroke1.randomSeed != stroke2.randomSeed) {
        RCTLogInfo(@"[RNPencilKit] Random seeds differ: %u vs %u", stroke1.randomSeed, stroke2.randomSeed);
        return NO;
    }
    RCTLogInfo(@"[RNPencilKit] Random seeds are equal.");
    
    // Compare mask (if any) – if both nil or equal, then it's fine.
    if ((stroke1.mask && ![stroke1.mask isEqual:stroke2.mask]) ||
        (!stroke1.mask && stroke2.mask)) {
        RCTLogInfo(@"[RNPencilKit] Masks differ: %@ vs %@", stroke1.mask, stroke2.mask);
        return NO;
    }
    RCTLogInfo(@"[RNPencilKit] Masks are equal.");
    
    // Compare maskedPathRanges arrays.
    if (stroke1.maskedPathRanges.count != stroke2.maskedPathRanges.count) {
        RCTLogInfo(@"[RNPencilKit] Masked path ranges counts differ: %lu vs %lu", (unsigned long)stroke1.maskedPathRanges.count, (unsigned long)stroke2.maskedPathRanges.count);
        return NO;
    }
    for (NSInteger i = 0; i < stroke1.maskedPathRanges.count; i++) {
        id range1 = stroke1.maskedPathRanges[i];
        id range2 = stroke2.maskedPathRanges[i];
        if (![range1 isEqual:range2]) {
            RCTLogInfo(@"[RNPencilKit] Masked path range at index %ld differ: %@ vs %@", (long)i, range1, range2);
            return NO;
        }
    }
    RCTLogInfo(@"[RNPencilKit] Masked path ranges are equal.");
    
    // Note: We intentionally ignore the transform because we apply it separately for multi-device support.
    RCTLogInfo(@"[RNPencilKit] Ignoring transform in comparison.");
    
    // If all checks pass, we consider the strokes equal.
    RCTLogInfo(@"[RNPencilKit] Strokes are considered equal by custom matching.");
    return YES;
}


- (void)applyStrokeDiffWithAddedStrokes:(NSArray<NSString *> *)addedStrokesBase64
                         removedStrokes:(NSArray<NSString *> *)removedStrokesBase64
{
    self.isProgrammaticUpdate = YES;
        PKDrawing *existingDrawing = _view.drawing;
    NSMutableArray<PKStroke *> *currentStrokes = [NSMutableArray arrayWithArray:existingDrawing.strokes];
    RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: Initial current strokes count: %lu",
               (unsigned long)currentStrokes.count);
    BOOL allRemovalsSuccessful = YES;
    for (NSString *removedStrokeBase64 in removedStrokesBase64) {
        RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: Removing stroke base64: %@", removedStrokeBase64);
        
        NSData *data = [[NSData alloc] initWithBase64EncodedString:removedStrokeBase64
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (!data) {
            RCTLogError(@"[RNPencilKit] applyStrokeDiff: Failed to decode base64 for removed stroke.");
            allRemovalsSuccessful = NO;
            continue;
        }
        
        NSError *error = nil;
        PKDrawing *incomingDrawing = [[PKDrawing alloc] initWithData:data error:&error];
        if (error || !incomingDrawing || incomingDrawing.strokes.count == 0) {
            RCTLogError(@"[RNPencilKit] applyStrokeDiff: Invalid removed stroke data.");
            allRemovalsSuccessful = NO;
            continue;
        }
        RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: The removed drawing has %lu stroke(s)",
                   (unsigned long)incomingDrawing.strokes.count);
                for (PKStroke *strokeToRemove in incomingDrawing.strokes) {
            BOOL foundAndRemoved = NO;
            for (PKStroke *existingStroke in [currentStrokes copy]) {
                if ([self stroke:existingStroke isEqualToStroke:strokeToRemove]) {
                    RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: Matched & removing stroke.");
                    [currentStrokes removeObject:existingStroke];
                    foundAndRemoved = YES;
                    break;
                }
            }
            if (!foundAndRemoved) {
                RCTLogWarn(@"[RNPencilKit] applyStrokeDiff: Removed stroke not found in current drawing.");
                allRemovalsSuccessful = NO;
            }
        }
    }
        if (!allRemovalsSuccessful) {
        RCTLogWarn(@"[RNPencilKit] applyStrokeDiff: Not all removals were successful. Aborting.");
        self.isProgrammaticUpdate = NO;
        return;
    }
    CGSize viewSize = _view.bounds.size;
    CGFloat hRatio = viewSize.width  / kDocWidth;   // e.g. 351 / 1131
    CGFloat vRatio = viewSize.height / kDocHeight;  // e.g. 497 / 1600
    CGFloat scale  = MIN(hRatio, vRatio);
    
    CGFloat scaledW = kDocWidth  * scale;
    CGFloat scaledH = kDocHeight * scale;
    CGFloat offsetX = (viewSize.width  - scaledW) / 2.0;
    CGFloat offsetY = (viewSize.height - scaledH) / 2.0;
    
    CGAffineTransform docToDevice = CGAffineTransformMakeTranslation(offsetX, offsetY);
    docToDevice = CGAffineTransformScale(docToDevice, scale, scale);
    
    for (NSString *addedStrokeBase64 in addedStrokesBase64) {
        RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: Adding stroke base64: %@", addedStrokeBase64);
        
        NSData *data = [[NSData alloc] initWithBase64EncodedString:addedStrokeBase64
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (!data) {
            RCTLogError(@"[RNPencilKit] applyStrokeDiff: Failed to decode base64 for added stroke.");
            continue;
        }
        
        NSError *error = nil;
        PKDrawing *docDrawing = [[PKDrawing alloc] initWithData:data error:&error];
        if (error || !docDrawing || docDrawing.strokes.count == 0) {
            RCTLogError(@"[RNPencilKit] applyStrokeDiff: Invalid added stroke data.");
            continue;
        }
        
        RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: The added drawing has %lu stroke(s)",
                   (unsigned long)docDrawing.strokes.count);
                PKDrawing *deviceDrawing = [docDrawing drawingByApplyingTransform:docToDevice];
        
        // 3) Append these new strokes to our in-memory stroke list
        [currentStrokes addObjectsFromArray:deviceDrawing.strokes];
    }

    PKDrawing *finalDrawing = [[PKDrawing alloc] initWithStrokes:currentStrokes];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_view setDrawing:finalDrawing];
     //   [_view.undoManager removeAllActions];
        _previousDrawing = finalDrawing;
        self.isProgrammaticUpdate = NO;
        RCTLogInfo(@"[RNPencilKit] applyStrokeDiff: Finished. Final stroke count: %lu",
                   (unsigned long)finalDrawing.strokes.count);
    });
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

  // 1) Prevent re-entrancy for programmatic updates
  if (self.isProgrammaticUpdate) {
    _previousDrawing = canvasView.drawing;
    return;
  }

  // 2) If we have an event emitter, proceed
  if (auto e = getEmitter(_eventEmitter)) {

    // A) Identify the old vs. new strokes
    NSArray<PKStroke *> *oldStrokes = _previousDrawing.strokes;
    NSArray<PKStroke *> *currentStrokes = canvasView.drawing.strokes;

    NSSet *oldSet = [NSSet setWithArray:oldStrokes];
    NSSet *newSet = [NSSet setWithArray:currentStrokes];

    NSMutableSet *removedSet = [oldSet mutableCopy];
    [removedSet minusSet:newSet]; // Strokes that were in old but not in new
    NSMutableSet *addedSet = [newSet mutableCopy];
    [addedSet minusSet:oldSet];   // Strokes that are new in current

    // B) Build the device→doc transform
    // First compute doc→device (aspect-fit)
    CGSize viewSize = _view.bounds.size;
    CGFloat hRatio = viewSize.width  / kDocWidth;   // e.g.  351 / 1131
    CGFloat vRatio = viewSize.height / kDocHeight;  // e.g.  497 / 1600
    CGFloat scale  = MIN(hRatio, vRatio);

    CGFloat scaledW = kDocWidth  * scale;
    CGFloat scaledH = kDocHeight * scale;
    CGFloat offsetX = (viewSize.width  - scaledW)  / 2.0;
    CGFloat offsetY = (viewSize.height - scaledH) / 2.0;

    CGAffineTransform docToDevice = CGAffineTransformMakeTranslation(offsetX, offsetY);
    docToDevice = CGAffineTransformScale(docToDevice, scale, scale);

    // Invert to get device→doc
    CGAffineTransform deviceToDoc = CGAffineTransformInvert(docToDevice);

    // C) Convert each removed stroke from device coords to doc coords
    std::vector<std::string> removedStrokesBase64;
    for (PKStroke *stroke in removedSet) {
      // Make a PKDrawing with just this stroke
      PKDrawing *tempDrawing = [[PKDrawing alloc] initWithStrokes:@[ stroke ]];

      // Transform it from device to doc
      PKDrawing *docDrawing = [tempDrawing drawingByApplyingTransform:deviceToDoc];

      // Encode docDrawing → NSData → base64
      NSData *strokeData = [docDrawing dataRepresentation];
      NSString *b64 = [strokeData base64EncodedStringWithOptions:0];
      removedStrokesBase64.push_back(std::string([b64 UTF8String]));
    }

    // D) Convert each added stroke from device coords to doc coords
    std::vector<std::string> addedStrokesBase64;
    for (PKStroke *stroke in addedSet) {
      PKDrawing *tempDrawing = [[PKDrawing alloc] initWithStrokes:@[ stroke ]];
      PKDrawing *docDrawing = [tempDrawing drawingByApplyingTransform:deviceToDoc];

      NSData *strokeData = [docDrawing dataRepresentation];
      NSString *b64 = [strokeData base64EncodedStringWithOptions:0];
      addedStrokesBase64.push_back(std::string([b64 UTF8String]));
    }

    // E) Emit event to JS with doc-coord strokes
    facebook::react::RNPencilKitEventEmitter::OnCanvasViewDrawingDidChange payload{};
    payload.addedStrokes = std::move(addedStrokesBase64);
    payload.removedStrokes = std::move(removedStrokesBase64);

    e->onCanvasViewDrawingDidChange(std::move(payload));

    // F) Update _previousDrawing
    _previousDrawing = canvasView.drawing;
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

    if ([commandName isEqualToString:@"loadStroke"]) {
      if (args.count == 1 && [args[0] isKindOfClass:[NSString class]]) {
        NSString *strokeBase64 = args[0];
        [self loadBase64Stroke:strokeBase64];
        return;
      }
    }
    
    if ([commandName isEqualToString:@"applyStrokeDiff"]) {
      if (args.count == 2 &&
          [args[0] isKindOfClass:[NSArray class]] &&
          [args[1] isKindOfClass:[NSArray class]]) {
        NSArray<NSString *> *addedStrokes = args[0];
        NSArray<NSString *> *removedStrokes = args[1];
        [self applyStrokeDiffWithAddedStrokes:addedStrokes removedStrokes:removedStrokes];
        return;
      }
    }
    
  RCTRNPencilKitHandleCommand(self, commandName, args);
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<RNPencilKitComponentDescriptor>();
}

Class<RCTComponentViewProtocol> RNPencilKitCls(void) {
  return RNPencilKit.class;
}

@end
