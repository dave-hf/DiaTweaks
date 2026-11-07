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

// What Dia itself painted, intensity included (Dia 1.56 blends a profile's intensity into these layers): read off the
// layer, or remembered while the layer still holds ours.
static char DPDiaGradientKey, DPDiaBaseKey;

// Dia's hue swapped for the profile's own, keeping how saturated, bright and opaque Dia made it.
static NSColor *DPInHue(NSColor *dia, NSColor *custom) {
    CGFloat h, s, b, a, dh, ds, db, da;
    [[custom colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getHue:&h saturation:&s brightness:&b alpha:&a];
    [[dia colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getHue:&dh saturation:&ds brightness:&db alpha:&da];
    return [NSColor colorWithColorSpace:NSColorSpace.sRGBColorSpace hue:h saturation:MIN(ds, s) brightness:db alpha:da];
}

static void DPPaintGradient(NSView *gradientView) {
    NSString *space = DPSpaceOfWindow(gradientView.window);
    NSColor *custom = DPProfileColor(space);
    CGFloat strength = DPProfileStrength(space);
    CAGradientLayer *layer = (CAGradientLayer *)[gradientView safeSwiftValueForKey:@"gradientLayer"];
    if (![layer isKindOfClass:CAGradientLayer.class]) return;
    NSArray *dia = DPDiaValue(layer, &DPDiaGradientKey, layer.colors);
    if (dia.count < 2) return;
    if (!custom && strength == 0) {
        if (![layer.colors isEqual:dia]) layer.colors = dia;  // a color or strength was just cleared
        return;
    }
    NSColor *top = [NSColor colorWithCGColor:(__bridge CGColorRef)dia.firstObject], *bottom = [NSColor colorWithCGColor:(__bridge CGColorRef)dia.lastObject];
    CGFloat topAlpha = top.alphaComponent, bottomAlpha = bottom.alphaComponent;
    if (custom) {
        top = DPLightened(custom, 0.25);
        bottom = custom;
    }
    topAlpha += strength * (1 - topAlpha);
    bottomAlpha += strength * (1 - bottomAlpha);
    NSArray *ours = @[ (__bridge id)[top colorWithAlphaComponent:topAlpha].CGColor, (__bridge id)[bottom colorWithAlphaComponent:bottomAlpha].CGColor ];
    layer.colors = ours;
    DPOverride(layer, &DPDiaGradientKey, dia, ours);
}

// Strength pulls the base toward a deep shade of the color in dark mode and a pale one in light mode. A custom color
// takes over any hue Dia's intensity gave the base.
static void DPPaintBase(NSView *base) {
    NSString *space = DPSpaceOfWindow(base.window);
    CGFloat strength = DPProfileStrength(space);
    NSColor *color = DPProfileColor(space);
    CALayer *layer = base.layer;
    id current = (__bridge id)layer.backgroundColor;
    id diaCG = DPDiaValue(layer, &DPDiaBaseKey, current);
    if (!diaCG) return;
    if (!color && strength == 0) {
        if (![current isEqual:diaCG]) layer.backgroundColor = (__bridge CGColorRef)diaCG;
        return;
    }
    NSColor *dia = [NSColor colorWithCGColor:(__bridge CGColorRef)diaCG];
    if (!color) {
        CAGradientLayer *gradient = [DPSubview(base.superview, DPDiaGradientView) safeSwiftValueForKey:@"gradientLayer"];
        NSArray *colors = [gradient isKindOfClass:CAGradientLayer.class] ? DPDiaValue(gradient, &DPDiaGradientKey, gradient.colors) : nil;
        color = colors.count ? [NSColor colorWithCGColor:(__bridge CGColorRef)colors.lastObject] : nil;
    }
    NSColor *painted = color ? DPInHue(dia, color) : dia;
    if (strength > 0 && color) {
        NSColor *target = DPIsDark(base) ? DPMix(color, NSColor.blackColor, 0.6) : DPMix(color, NSColor.whiteColor, 0.6);
        painted = [DPMix([painted colorWithAlphaComponent:1], target, strength * 0.85) colorWithAlphaComponent:dia.alphaComponent + strength * 0.25];
    }
    id ours = (__bridge id)painted.CGColor;
    layer.backgroundColor = (__bridge CGColorRef)ours;
    DPOverride(layer, &DPDiaBaseKey, diaCG, ours);
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
