// Edit Profile: more swatches and a Custom one under Dia's Theme Color, and a Color Strength slider.
#import "Patches/ProfileColors/ProfileColors.h"

static char DPSpaceKey, DPRowsKey;
@class DPColorRows;
static DPColorRows *DPPanelOwner;  // The color panel doesn't keep its target, and outlives the pane.
static const CGFloat DPSwatch = 26;  // Dia's 20-point swatches, 6 apart, with room for the selection ring.

@interface DPColorSwatch : NSControl
@property(nonatomic, strong) NSColor *color;  // nil: Custom
@property(nonatomic) BOOL selected;
@end

@implementation DPColorSwatch
- (NSSize)intrinsicContentSize { return NSMakeSize(DPSwatch, DPSwatch); }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { [self sendAction:self.action to:self.target]; }
- (void)setSelected:(BOOL)selected { _selected = selected; self.needsDisplay = YES; }
- (void)setColor:(NSColor *)color { _color = color; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirty {
    NSRect dot = NSInsetRect(self.bounds, 3, 3);
    if (self.color) {
        [self.color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    } else {  // a color wheel
        for (int i = 0; i < 36; i++) {
            NSBezierPath *slice = [NSBezierPath bezierPath];
            NSPoint center = NSMakePoint(NSMidX(dot), NSMidY(dot));
            [slice moveToPoint:center];
            [slice appendBezierPathWithArcWithCenter:center radius:NSWidth(dot) / 2 startAngle:i * 10 endAngle:(i + 1) * 10 + 0.5];
            [[NSColor colorWithHue:i / 36.0 saturation:0.75 brightness:0.95 alpha:1] setFill];
            [slice fill];
        }
    }
    if (self.selected) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 0.75, 0.75)];
        ring.lineWidth = 1.5;
        [NSColor.labelColor setStroke];
        [ring stroke];
    }
}
@end

// What the pane's rows need to stay in step.
@interface DPColorRows : NSObject
@property(nonatomic, copy) NSString *spaceID;
@property(nonatomic, strong) NSArray<DPColorSwatch *> *swatches;
@property(nonatomic, weak) NSView *picker;
@end

@implementation DPColorRows
- (void)sync {
    NSColor *custom = DPProfileColor(self.spaceID);
    BOOL preset = NO;
    for (DPColorSwatch *swatch in self.swatches) {
        if (!swatch.color) continue;
        swatch.selected = DPSameColor(swatch.color, custom);
        preset = preset || swatch.selected;
    }
    self.swatches.lastObject.selected = custom && !preset;
    for (NSView *option in self.picker.subviews.firstObject.subviews) option.needsDisplay = YES;  // Dia's ring hides while a color of ours is on
}

- (void)pick:(DPColorSwatch *)swatch {
    if (swatch.color) {
        DPSetProfileColor(self.spaceID, swatch.color);
    } else {
        NSColorPanel *panel = NSColorPanel.sharedColorPanel;
        panel.showsAlpha = NO;
        if (DPProfileColor(self.spaceID)) panel.color = DPProfileColor(self.spaceID);
        DPPanelOwner = self;
        [panel setTarget:self];
        [panel setAction:@selector(panelChanged:)];
        panel.continuous = YES;
        [panel orderFront:nil];
    }
    [self sync];
}

- (void)panelChanged:(NSColorPanel *)panel {
    DPSetProfileColor(self.spaceID, panel.color);
    [self sync];
}

- (void)strengthChanged:(NSSlider *)slider { DPSetProfileStrength(self.spaceID, slider.doubleValue); }
@end

static NSView *DPColorRow(NSTextField *title, NSString *text, NSView *control, CGFloat height, CGFloat trailing) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = title.font;
    label.textColor = title.textColor;
    NSView *row = [NSView new];
    for (NSView *view in @[ label, control ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:height],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:trailing], [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static NSStackView *DPSwatchGrid(DPColorRows *rows) {
    NSMutableArray<DPColorSwatch *> *swatches = [NSMutableArray array];
    for (id color in [DPMoreProfileColors() arrayByAddingObject:(id)NSNull.null]) {
        DPColorSwatch *swatch = [DPColorSwatch new];
        swatch.color = color == NSNull.null ? nil : color;
        swatch.target = rows;
        swatch.action = @selector(pick:);
        DPSetHint(swatch, swatch.color ? nil : @"Any color");
        [swatches addObject:swatch];
    }
    rows.swatches = swatches;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < swatches.count; i += 8) {
        NSStackView *line = [NSStackView stackViewWithViews:[swatches subarrayWithRange:NSMakeRange(i, MIN(8, swatches.count - i))]];
        line.spacing = 0;
        [lines addObject:line];
    }
    NSStackView *grid = [NSStackView stackViewWithViews:lines];
    grid.orientation = NSUserInterfaceLayoutOrientationVertical;
    grid.alignment = NSLayoutAttributeLeading;
    grid.spacing = 0;
    return grid;
}

static void DPAddColorRows(NSViewController *pane) {
    NSView *picker = DPFindView(pane.view, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaThemePicker); });
    // The Theme Color row is the picker's ancestor whose parent is the group's vertical stack of rows.
    NSView *themeRow = picker;
    while (themeRow.superview && !([themeRow.superview isKindOfClass:NSStackView.class]
                                   && ((NSStackView *)themeRow.superview).orientation == NSUserInterfaceLayoutOrientationVertical))
        themeRow = themeRow.superview;
    NSStackView *rows = (NSStackView *)themeRow.superview;
    NSTextField *title = (NSTextField *)DPFindView(themeRow, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    NSString *spaceID = [[pane safeSwiftValueForKey:@"spaceID"] description];
    if (!picker || !rows || !title || !spaceID || DPGet(pane, &DPRowsKey)) return;

    DPColorRows *state = [DPColorRows new];
    state.spaceID = spaceID;
    state.picker = picker;
    DPSet(picker, &DPSpaceKey, spaceID);
    DPSet(pane, &DPRowsKey, state);

    NSSlider *slider = [NSSlider sliderWithValue:DPProfileStrength(spaceID) minValue:0 maxValue:1 target:state action:@selector(strengthChanged:)];
    slider.continuous = YES;
    [slider.widthAnchor constraintEqualToConstant:202].active = YES;
    NSUInteger index = [rows.arrangedSubviews indexOfObject:themeRow] + 1;
    NSArray *added = @[ [NSBox new], DPColorRow(title, @"More Colors", DPSwatchGrid(state), 2 * DPSwatch + 16, 3),
                        [NSBox new], DPColorRow(title, @"Color Strength", slider, 42, 0) ];
    for (NSView *view in added) {
        if ([view isKindOfClass:NSBox.class]) ((NSBox *)view).boxType = NSBoxSeparator;
        [rows insertArrangedSubview:view atIndex:index++];
        [view.widthAnchor constraintEqualToAnchor:rows.widthAnchor].active = YES;
    }
    [state sync];
}

static NSString *DPSpaceOfPicker(NSView *view) {
    for (; view; view = view.superview) if (DPGet(view, &DPSpaceKey)) return DPGet(view, &DPSpaceKey);
    return nil;
}

static void DPProfilePane_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPProfilePane_viewDidLoad, self);
    if (DPProfileColors.on) DPAddColorRows(self);
}

// Choosing one of Dia's themes goes back to it.
static void DPThemePicker_themeClicked(NSView *self, SEL _cmd, id sender) {
    DPCallOriginal(DPThemePicker_themeClicked, self, sender);
    NSString *spaceID = DPSpaceOfPicker(self);
    if (!spaceID || !DPProfileColor(spaceID)) return;
    DPSetProfileColor(spaceID, nil);
    for (NSResponder *next = self.nextResponder; next; next = next.nextResponder)
        if ([next isKindOfClass:NSViewController.class] && DPGet(next, &DPRowsKey)) [(DPColorRows *)DPGet(next, &DPRowsKey) sync];
}

static void DPThemeOption_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPThemeOption_updateLayer, self);
    CALayer *ring = [self safeSwiftValueForKey:@"$__lazy_storage_$_selectionRingLayer"];
    if ([ring isKindOfClass:CALayer.class]) ring.hidden = DPProfileColor(DPSpaceOfPicker(self)) != nil;
}

void DPInstallProfileColorPicker(void) {
    DPHook(DPDiaProfilePane, @selector(viewDidLoad), (IMP)DPProfilePane_viewDidLoad);
    DPHook(DPDiaThemePicker, @selector(themeClicked:), (IMP)DPThemePicker_themeClicked);
    DPHook(DPDiaThemeOption, @selector(updateLayer), (IMP)DPThemeOption_updateLayer);
}
