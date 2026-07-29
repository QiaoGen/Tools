#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

#include "CadModel.hpp"

#include <algorithm>
#include <memory>
#include <simd/simd.h>

namespace {

struct ViewUniforms {
  simd_float2 center;
  float scale;
  float padding;
  simd_float2 viewport;
  simd_float2 pan;
};

NSString* const kMetalSource = @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float2 position [[attribute(0)]];
  float4 color [[attribute(1)]];
};

struct VertexOut {
  float4 position [[position]];
  float4 color;
};

struct ViewUniforms {
  float2 center;
  float scale;
  float padding;
  float2 viewport;
  float2 pan;
};

vertex VertexOut cad_vertex(VertexIn input [[stage_in]], constant ViewUniforms& view [[buffer(1)]]) {
  float2 pixel = (input.position - view.center) * view.scale + view.viewport * 0.5 + view.pan;
  float2 ndc = float2(pixel.x / view.viewport.x * 2.0 - 1.0,
                      pixel.y / view.viewport.y * 2.0 - 1.0);
  VertexOut output;
  output.position = float4(ndc, 0.0, 1.0);
  output.color = input.color;
  return output;
}

fragment float4 cad_fragment(VertexOut input [[stage_in]]) {
  return input.color;
}
)METAL";

}  // namespace

@class CadCanvasView;

@interface CadMetalRenderer : NSObject <MTKViewDelegate>
@property(nonatomic, weak) CadCanvasView* owner;
- (instancetype)initWithView:(MTKView*)view;
- (void)setScene:(std::shared_ptr<cad::Scene>)scene;
@end

@interface CadOverlayView : NSView
@property(nonatomic, weak) CadCanvasView* owner;
@end

@interface CadCanvasView : NSView <NSDraggingDestination>
@property(nonatomic, strong) MTKView* metalView;
@property(nonatomic, strong) CadMetalRenderer* renderer;
@property(nonatomic, strong) CadOverlayView* overlay;
@property(nonatomic, strong) NSView* topBar;
@property(nonatomic, strong) NSTextField* fileLabel;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSTextField* emptyTitle;
@property(nonatomic, strong) NSTextField* emptyHelp;
@property(nonatomic, strong) NSProgressIndicator* spinner;
@property(nonatomic, strong) NSButton* zoomInButton;
@property(nonatomic, strong) NSButton* zoomOutButton;
@property(nonatomic, strong) NSButton* fitButton;
@property(nonatomic) std::shared_ptr<cad::Scene> scene;
@property(nonatomic) double zoomScale;
@property(nonatomic) NSPoint pan;
@property(nonatomic) NSPoint lastMouse;
- (void)openDocument:(id)sender;
- (void)loadURL:(NSURL*)url;
- (void)fitDrawing:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
@end

@implementation CadMetalRenderer {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  id<MTLRenderPipelineState> _pipeline;
  id<MTLBuffer> _vertexBuffer;
  NSUInteger _vertexCount;
}

- (instancetype)initWithView:(MTKView*)view {
  self = [super init];
  if (!self) return nil;
  _device = view.device;
  _queue = [_device newCommandQueue];

  NSError* error = nil;
  id<MTLLibrary> library = [_device newLibraryWithSource:kMetalSource options:nil error:&error];
  if (!library) {
    NSLog(@"Metal shader error: %@", error.localizedDescription);
    return self;
  }

  MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:@"cad_vertex"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"cad_fragment"];
  descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;

  MTLVertexDescriptor* vertices = [MTLVertexDescriptor vertexDescriptor];
  vertices.attributes[0].format = MTLVertexFormatFloat2;
  vertices.attributes[0].offset = offsetof(cad::Vertex, x);
  vertices.attributes[0].bufferIndex = 0;
  vertices.attributes[1].format = MTLVertexFormatFloat4;
  vertices.attributes[1].offset = offsetof(cad::Vertex, r);
  vertices.attributes[1].bufferIndex = 0;
  vertices.layouts[0].stride = sizeof(cad::Vertex);
  descriptor.vertexDescriptor = vertices;
  _pipeline = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (!_pipeline) NSLog(@"Metal pipeline error: %@", error.localizedDescription);
  return self;
}

- (void)setScene:(std::shared_ptr<cad::Scene>)scene {
  _vertexBuffer = nil;
  _vertexCount = 0;
  if (!scene || scene->lineVertices.empty()) return;
  _vertexCount = scene->lineVertices.size();
  _vertexBuffer = [_device newBufferWithBytes:scene->lineVertices.data()
                                         length:scene->lineVertices.size() * sizeof(cad::Vertex)
                                        options:MTLResourceStorageModeShared];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

- (void)drawInMTKView:(MTKView*)view {
  MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
  id<CAMetalDrawable> drawable = view.currentDrawable;
  if (!pass || !drawable || !_pipeline) return;

  pass.colorAttachments[0].clearColor = MTLClearColorMake(0.035, 0.048, 0.040, 1.0);
  id<MTLCommandBuffer> command = [_queue commandBuffer];
  id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
  [encoder setRenderPipelineState:_pipeline];

  CadCanvasView* owner = self.owner;
  if (_vertexBuffer && _vertexCount > 0 && owner.scene) {
    const NSSize size = view.bounds.size;
    ViewUniforms uniforms;
    uniforms.center = {(float)owner.scene->fitBounds.centerX(), (float)owner.scene->fitBounds.centerY()};
    uniforms.scale = (float)owner.zoomScale;
    uniforms.padding = 0;
    uniforms.viewport = {(float)size.width, (float)size.height};
    uniforms.pan = {(float)owner.pan.x, (float)owner.pan.y};
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:_vertexCount];
  }

  [encoder endEncoding];
  [command presentDrawable:drawable];
  [command commit];
}

@end

@implementation CadOverlayView

- (BOOL)isFlipped { return NO; }
- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  CadCanvasView* owner = self.owner;
  if (!owner.scene || owner.scene->labels.empty()) return;

  const NSSize size = self.bounds.size;
  const double centerX = owner.scene->fitBounds.centerX();
  const double centerY = owner.scene->fitBounds.centerY();
  NSUInteger drawn = 0;
  for (const auto& label : owner.scene->labels) {
    if (drawn >= 1200) break;
    const double x = (label.x - centerX) * owner.zoomScale + size.width * 0.5 + owner.pan.x;
    const double y = (label.y - centerY) * owner.zoomScale + size.height * 0.5 + owner.pan.y;
    if (x < -100 || y < -100 || x > size.width + 100 || y > size.height + 100) continue;
    const CGFloat fontSize = std::clamp(label.height * owner.zoomScale, 5.0, 48.0);
    if (fontSize < 5.2) continue;
    NSString* value = [NSString stringWithUTF8String:label.text.c_str()];
    if (!value.length) continue;
    NSColor* color = [NSColor colorWithRed:label.color.r green:label.color.g blue:label.color.b alpha:0.92];
    NSDictionary* attributes = @{
      NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: color
    };
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform* transform = [NSAffineTransform transform];
    [transform translateXBy:x yBy:y];
    [transform rotateByRadians:label.angle];
    [transform concat];
    [value drawAtPoint:NSZeroPoint withAttributes:attributes];
    [NSGraphicsContext restoreGraphicsState];
    ++drawn;
  }
}

@end

@implementation CadCanvasView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;

  self.wantsLayer = YES;
  self.layer.backgroundColor = [NSColor colorWithRed:0.035 green:0.048 blue:0.040 alpha:1].CGColor;
  self.zoomScale = 1;
  self.pan = NSZeroPoint;
  [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

  self.topBar = [[NSView alloc] initWithFrame:NSZeroRect];
  self.topBar.wantsLayer = YES;
  self.topBar.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.073 blue:0.060 alpha:1].CGColor;
  [self addSubview:self.topBar];

  NSTextField* brand = [NSTextField labelWithString:@"△  CadReader"];
  brand.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  brand.textColor = [NSColor colorWithRed:0.84 green:1.0 blue:0.27 alpha:1];
  [self.topBar addSubview:brand];
  brand.translatesAutoresizingMaskIntoConstraints = NO;

  self.fileLabel = [NSTextField labelWithString:@"未打开图纸"];
  self.fileLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  self.fileLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1];
  self.fileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [self.topBar addSubview:self.fileLabel];
  self.fileLabel.translatesAutoresizingMaskIntoConstraints = NO;

  NSButton* openButton = [NSButton buttonWithTitle:@"打开 DWG" target:self action:@selector(openDocument:)];
  openButton.bezelStyle = NSBezelStyleTexturedRounded;
  openButton.keyEquivalent = @"o";
  openButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  [self.topBar addSubview:openButton];
  openButton.translatesAutoresizingMaskIntoConstraints = NO;

  [NSLayoutConstraint activateConstraints:@[
    [brand.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:18],
    [brand.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
    [self.fileLabel.centerXAnchor constraintEqualToAnchor:self.topBar.centerXAnchor],
    [self.fileLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
    [self.fileLabel.widthAnchor constraintLessThanOrEqualToConstant:480],
    [openButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-16],
    [openButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor]
  ]];

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  self.metalView = [[MTKView alloc] initWithFrame:NSZeroRect device:device];
  self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  self.metalView.sampleCount = 1;
  self.metalView.preferredFramesPerSecond = 60;
  self.metalView.enableSetNeedsDisplay = YES;
  self.metalView.paused = YES;
  [self addSubview:self.metalView];

  self.renderer = [[CadMetalRenderer alloc] initWithView:self.metalView];
  self.renderer.owner = self;
  self.metalView.delegate = self.renderer;

  self.overlay = [[CadOverlayView alloc] initWithFrame:NSZeroRect];
  self.overlay.owner = self;
  self.overlay.wantsLayer = YES;
  self.overlay.layer.backgroundColor = NSColor.clearColor.CGColor;
  [self addSubview:self.overlay];

  self.emptyTitle = [NSTextField labelWithString:@"把 DWG 图纸拖到这里"];
  self.emptyTitle.font = [NSFont systemFontOfSize:28 weight:NSFontWeightMedium];
  self.emptyTitle.textColor = [NSColor colorWithWhite:0.9 alpha:1];
  self.emptyTitle.alignment = NSTextAlignmentCenter;
  [self addSubview:self.emptyTitle];

  self.emptyHelp = [NSTextField labelWithString:@"本地 C++ 解析 · Metal 渲染 · 文件不会上传"];
  self.emptyHelp.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
  self.emptyHelp.textColor = [NSColor colorWithWhite:0.43 alpha:1];
  self.emptyHelp.alignment = NSTextAlignmentCenter;
  [self addSubview:self.emptyHelp];

  self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
  self.spinner.style = NSProgressIndicatorStyleSpinning;
  self.spinner.controlSize = NSControlSizeRegular;
  self.spinner.hidden = YES;
  [self addSubview:self.spinner];

  self.statusLabel = [NSTextField labelWithString:@"等待图纸 · 滚轮缩放 · 鼠标拖动"];
  self.statusLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
  self.statusLabel.textColor = [NSColor colorWithWhite:0.45 alpha:1];
  self.statusLabel.alignment = NSTextAlignmentCenter;
  [self addSubview:self.statusLabel];

  self.zoomInButton = [NSButton buttonWithTitle:@"＋" target:self action:@selector(zoomIn:)];
  self.zoomOutButton = [NSButton buttonWithTitle:@"−" target:self action:@selector(zoomOut:)];
  self.fitButton = [NSButton buttonWithTitle:@"适配" target:self action:@selector(fitDrawing:)];
  for (NSButton* button in @[self.zoomInButton, self.zoomOutButton, self.fitButton]) {
    button.bezelStyle = NSBezelStyleTexturedRounded;
    [self addSubview:button];
  }

  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)layout {
  [super layout];
  const CGFloat top = 58;
  const CGFloat bottom = 28;
  self.topBar.frame = NSMakeRect(0, 0, self.bounds.size.width, top);
  NSRect canvas = NSMakeRect(0, top, self.bounds.size.width, std::max(0.0, self.bounds.size.height - top - bottom));
  self.metalView.frame = canvas;
  self.overlay.frame = canvas;

  self.emptyTitle.frame = NSMakeRect(20, NSMidY(canvas) - 42, self.bounds.size.width - 40, 40);
  self.emptyHelp.frame = NSMakeRect(20, NSMidY(canvas) + 8, self.bounds.size.width - 40, 24);
  self.spinner.frame = NSMakeRect(NSMidX(self.bounds) - 10, NSMidY(canvas) - 82, 20, 20);
  self.statusLabel.frame = NSMakeRect(12, self.bounds.size.height - bottom + 6, self.bounds.size.width - 24, 16);

  NSArray<NSButton*>* buttons = @[
    self.zoomInButton,
    self.zoomOutButton,
    self.fitButton
  ];
  CGFloat x = self.bounds.size.width - 62;
  CGFloat y = self.bounds.size.height - bottom - 112;
  for (NSButton* button in buttons) {
    button.frame = NSMakeRect(x, y, 48, 30);
    y += 34;
  }
}

- (void)openDocument:(id)sender {
  (void)sender;
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.allowedFileTypes = @[@"dwg", @"dxf"];
  panel.allowsMultipleSelection = NO;
  panel.canChooseDirectories = NO;
  if ([panel runModal] == NSModalResponseOK) [self loadURL:panel.URL];
}

- (void)loadURL:(NSURL*)url {
  if (!url.isFileURL) return;
  NSString* extension = url.pathExtension.lowercaseString;
  if (!([extension isEqualToString:@"dwg"] || [extension isEqualToString:@"dxf"])) {
    NSBeep();
    self.statusLabel.stringValue = @"仅支持 DWG 或 DXF 文件";
    return;
  }

  self.fileLabel.stringValue = url.lastPathComponent;
  self.statusLabel.stringValue = @"正在使用 C++ 后台解析图纸…";
  self.emptyTitle.hidden = YES;
  self.emptyHelp.hidden = YES;
  self.spinner.hidden = NO;
  [self.spinner startAnimation:nil];
  const std::string path(url.fileSystemRepresentation);

  __weak CadCanvasView* weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    cad::LoadResult result = cad::loadDrawing(path);
    dispatch_async(dispatch_get_main_queue(), ^{
      CadCanvasView* strongSelf = weakSelf;
      if (!strongSelf) return;
      [strongSelf.spinner stopAnimation:nil];
      strongSelf.spinner.hidden = YES;
      if (!result.scene) {
        strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"读取失败：%s", result.error.c_str()];
        strongSelf.emptyTitle.stringValue = @"无法读取此图纸";
        strongSelf.emptyTitle.hidden = NO;
        strongSelf.emptyHelp.hidden = NO;
        return;
      }
      strongSelf.scene = result.scene;
      [strongSelf.renderer setScene:result.scene];
      [strongSelf fitDrawing:nil];
      NSString* suffix = result.scene->truncated ? @" · 超大图纸已限制细节" : @"";
      strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"已就绪 · %.1f 秒 · %zu 个图元 · %zu 个图层%@",
                                             result.elapsedSeconds, result.scene->entityCount, result.scene->layerCount, suffix];
      [strongSelf.metalView setNeedsDisplay:YES];
      [strongSelf.overlay setNeedsDisplay:YES];
    });
  });
}

- (void)fitDrawing:(id)sender {
  (void)sender;
  if (!self.scene || !self.scene->fitBounds.valid) return;
  const double width = std::max(1.0, self.scene->fitBounds.width());
  const double height = std::max(1.0, self.scene->fitBounds.height());
  self.zoomScale = std::max(1e-9, std::min((self.metalView.bounds.size.width - 80) / width,
                                          (self.metalView.bounds.size.height - 80) / height));
  self.pan = NSZeroPoint;
  [self.metalView setNeedsDisplay:YES];
  [self.overlay setNeedsDisplay:YES];
}

- (void)zoomBy:(double)factor anchor:(NSPoint)anchor {
  if (!self.scene) return;
  const NSPoint local = [self convertPoint:anchor toView:self.metalView];
  const NSSize size = self.metalView.bounds.size;
  const double oldScale = self.zoomScale;
  const double newScale = std::clamp(oldScale * factor, 1e-9, 1e8);
  const double worldX = (local.x - size.width * 0.5 - self.pan.x) / oldScale;
  const double worldY = (size.height - local.y - size.height * 0.5 - self.pan.y) / oldScale;
  self.pan = NSMakePoint(self.pan.x + worldX * (oldScale - newScale),
                         self.pan.y + worldY * (oldScale - newScale));
  self.zoomScale = newScale;
  [self.metalView setNeedsDisplay:YES];
  [self.overlay setNeedsDisplay:YES];
}

- (void)zoomIn:(id)sender { (void)sender; [self zoomBy:1.25 anchor:NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds))]; }
- (void)zoomOut:(id)sender { (void)sender; [self zoomBy:0.8 anchor:NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds))]; }

- (void)scrollWheel:(NSEvent*)event {
  const double delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8.0;
  [self zoomBy:std::exp(delta * 0.012) anchor:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseDown:(NSEvent*)event {
  self.lastMouse = [self convertPoint:event.locationInWindow fromView:nil];
  if (event.clickCount == 2) [self fitDrawing:nil];
}

- (void)mouseDragged:(NSEvent*)event {
  NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
  self.pan = NSMakePoint(self.pan.x + current.x - self.lastMouse.x,
                         self.pan.y - (current.y - self.lastMouse.y));
  self.lastMouse = current;
  [self.metalView setNeedsDisplay:YES];
  [self.overlay setNeedsDisplay:YES];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  NSArray<NSURL*>* urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                   options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
  if (!urls.count) return NSDragOperationNone;
  NSString* extension = urls.firstObject.pathExtension.lowercaseString;
  return ([extension isEqualToString:@"dwg"] || [extension isEqualToString:@"dxf"])
             ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSArray<NSURL*>* urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                   options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
  if (!urls.count) return NO;
  [self loadURL:urls.firstObject];
  return YES;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) CadCanvasView* canvas;
@property(nonatomic, strong) NSURL* pendingURL;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;
  NSRect frame = NSMakeRect(0, 0, 1180, 780);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.title = @"CadReader";
  self.window.minSize = NSMakeSize(720, 480);
  self.window.titlebarAppearsTransparent = YES;
  self.window.titleVisibility = NSWindowTitleHidden;
  self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.048 blue:0.040 alpha:1];

  self.canvas = [[CadCanvasView alloc] initWithFrame:frame];
  self.canvas.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.window.contentView = self.canvas;
  [self.window center];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  if (self.pendingURL) {
    [self.canvas loadURL:self.pendingURL];
    self.pendingURL = nil;
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (void)application:(NSApplication*)application openURLs:(NSArray<NSURL*>*)urls {
  (void)application;
  if (!urls.count) return;
  if (self.canvas) [self.canvas loadURL:urls.firstObject];
  else self.pendingURL = urls.firstObject;
}

@end

int main(int argc, const char* argv[]) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    NSApplication* application = [NSApplication sharedApplication];
    application.activationPolicy = NSApplicationActivationPolicyRegular;
    AppDelegate* delegate = [AppDelegate new];
    application.delegate = delegate;
    [application run];
  }
  return 0;
}
