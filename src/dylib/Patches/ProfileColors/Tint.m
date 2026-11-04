// Paints a profile's color and strength over the window's tint, after Dia paints its own.
#import "Patches/ProfileColors/ProfileColors.h"

static char DPSwitcherKey, DPSelectedKey;

// The profile a window shows: the selected item of its profile switcher, which stays up to date while hidden.
static NSString *DPSpaceOfWindow(NSWindow *window) {
    NSView *switcher = DPGet(window, &DPSwitcherKey);
    if (switcher.window != window) {
        switcher = DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSpaceSwitcher); });
        DPSet(window, &DPSwitcherKey, switcher);
    }
    NSDictionary *items = [switcher safeSwiftValueForKey:@"itemViews"];
    if (![items isKindOfClass:NSDictionary.class]) return nil;
    for (id key in items)
        if ([[items[key] safeSwiftValueForKey:@"isSelected"] boolValue]) return [key description];
    return items.count == 1 ? [items.allKeys.firstObject description] : nil;
}

static CGColorRef DPResolved(NSColor *color, NSView *view) {
    __block CGColorRef resolved = NULL;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{ resolved = color.CGColor; }];
    return resolved;
}

static NSColor *DPMix(NSColor *a, NSColor *b, CGFloat amount) {
    return [[a colorUsingColorSpace:NSColorSpace.sRGBColorSpace] blendedColorWithFraction:amount ofColor:[b colorUsingColorSpace:NSColorSpace.sRGBColorSpace]] ?: a;
}

// Dia lightens the top of the gradient by 0.25 lightness (HSL).
static NSColor *DPLightened(NSColor *color, CGFloat delta) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat h, s, b, a;
    [rgb getHue:&h saturation:&s brightness:&b alpha:&a];
    CGFloat l = b * (1 - s / 2), sl = (l == 0 || l == 1) ? 0 : (b - l) / MIN(l, 1 - l);
    l = MIN(1, l + delta);
    CGFloat nb = l + sl * MIN(l, 1 - l), ns = nb == 0 ? 0 : 2 * (1 - l / nb);
    return [NSColor colorWithColorSpace:NSColorSpace.sRGBColorSpace hue:h saturation:ns brightness:nb alpha:a];
}

static BOOL DPIsDark(NSView *view) {
    return [[view.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] isEqual:NSAppearanceNameDarkAqua];
}

static void DPPaintGradient(NSView *gradientView) {
    NSString *space = DPSpaceOfWindow(gradientView.window);
    NSColor *custom = DPProfileColor(space);
    CGFloat strength = DPProfileStrength(space);
    CAGradientLayer *layer = (CAGradientLayer *)[gradientView safeSwiftValueForKey:@"gradientLayer"];
    NSArray *dia = [gradientView safeSwiftValueForKey:@"colors"];
    if ((!custom && strength == 0) || ![layer isKindOfClass:CAGradientLayer.class] || ![dia isKindOfClass:NSArray.class] || dia.count < 2) return;
    NSColor *top = [NSColor colorWithCGColor:DPResolved(dia.firstObject, gradientView)], *bottom = [NSColor colorWithCGColor:DPResolved(dia.lastObject, gradientView)];
    CGFloat alpha = bottom.alphaComponent;
    if (custom) {
        top = DPLightened(custom, 0.25);
        bottom = custom;
    }
    alpha += strength * (1 - alpha);
    layer.colors = @[ (__bridge id)[top colorWithAlphaComponent:alpha].CGColor, (__bridge id)[bottom colorWithAlphaComponent:alpha].CGColor ];
}

// Toward a deep shade of the color in dark mode and a pale one in light mode, so strength shows in both.
static void DPPaintBase(NSView *base) {
    NSString *space = DPSpaceOfWindow(base.window);
    CGFloat strength = DPProfileStrength(space);
    NSColor *dia = [base safeSwiftValueForKey:@"backgroundColor"];
    if (strength == 0 || ![dia isKindOfClass:NSColor.class]) return;
    NSColor *diaColor = [NSColor colorWithCGColor:DPResolved(dia, base)];
    NSColor *color = DPProfileColor(space);
    if (!color) {
        NSView *gradient = DPSubview(base.superview, DPDiaGradientView);
        NSArray *colors = [gradient safeSwiftValueForKey:@"colors"];
        color = [colors isKindOfClass:NSArray.class] && colors.count ? [NSColor colorWithCGColor:DPResolved(colors.lastObject, base)] : nil;
    }
    if (!color) return;
    NSColor *target = DPIsDark(base) ? DPMix(color, NSColor.blackColor, 0.6) : DPMix(color, NSColor.whiteColor, 0.6);
    CGFloat alpha = diaColor.alphaComponent + strength * 0.25;
    base.layer.backgroundColor = [DPMix([diaColor colorWithAlphaComponent:1], target, strength * 0.85) colorWithAlphaComponent:alpha].CGColor;
}

static void DPGradient_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGradient_updateLayer, self);
    if (DPIsKind(self.superview, DPDiaWindowTint)) DPPaintGradient(self);
}

static void DPBase_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBase_updateLayer, self);
    if (DPIsKind(self.superview, DPDiaWindowTint)) DPPaintBase(self);
}

static void DPRepaintTint(NSView *tint) {
    for (NSView *sub in tint.subviews)
        if (DPIsKind(sub, DPDiaGradientView) || DPIsKind(sub, DPDiaBackgroundColor)) sub.needsDisplay = YES;
}

static void DPTint_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTint_layout, self);
    DPRepaintTint(self);
}

void DPRepaintProfileColors(void) {
    for (NSView *tint in DPFindViews(DPDiaWindowTint)) DPRepaintTint(tint);
}

// Switching profiles selects another switcher item; the tint may repaint before that, so it repaints again after.
static void DPSwitcherItem_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSwitcherItem_updateLayer, self);
    NSNumber *selected = [self safeSwiftValueForKey:@"isSelected"];
    if (![selected isKindOfClass:NSNumber.class] || [DPGet(self, &DPSelectedKey) isEqual:selected]) return;
    DPSet(self, &DPSelectedKey, selected);
    if (selected.boolValue) dispatch_async(dispatch_get_main_queue(), ^{ DPRepaintProfileColors(); });
}

void DPInstallProfileColorTint(void) {
    DPHook(DPDiaGradientView, @selector(updateLayer), (IMP)DPGradient_updateLayer);
    DPHook(DPDiaBackgroundColor, @selector(updateLayer), (IMP)DPBase_updateLayer);
    DPHook(DPDiaWindowTint, @selector(layout), (IMP)DPTint_layout);
    DPHook(DPDiaSpaceSwitcherItem, @selector(updateLayer), (IMP)DPSwitcherItem_updateLayer);
}
