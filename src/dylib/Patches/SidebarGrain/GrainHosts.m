#import "SidebarGrain.h"

NSHashTable<NSView *> *DPGrainHosts;
static char DPGrainViewKey;

// The footer sits beside the page, never in the page or the strip, so the search skips both.
static BOOL DPHasSidebarFooter(NSView *view, NSView *strip) {
    if (DPIsKind(view, DPDiaSidebarFooter)) return YES;
    if (view == strip || DPIsKind(view, DPDiaContentContainer)) return NO;
    for (NSView *sub in view.subviews) if (DPHasSidebarFooter(sub, strip)) return YES;
    return NO;
}

BOOL DPGrainHostAvailable(NSView *host) {
    if (!host.window) return NO;
    // A hidden, auto-hiding sidebar is still a vertical layout.
    if (DPIsKind(host, DPDiaTabStrip)) return !DPHasSidebarFooter(host.window.contentView, host);
    return DPSubview(host, DPDiaSidebarFooter) != nil;
}

NSRect DPGrainHostBounds(NSView *host) {
    NSRect bounds = host.bounds;
    if (!DPIsKind(host, DPDiaTabStrip)) return bounds;
    NSView *content = DPFindView(host.window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaContentContainer);
    });
    if (!content) return NSZeroRect;
    NSRect page = [host convertRect:content.bounds fromView:content];
    // Dia's strip extends below its visible chrome to feather tab shadows.
    // Keep the texture above the actual page boundary, not that larger root.
    CGFloat edge = host.isFlipped ? NSMinY(page) : NSMaxY(page);
    NSRect chrome = host.isFlipped ? NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), MAX(0, edge - NSMinY(bounds))) :
        NSMakeRect(NSMinX(bounds), MAX(NSMinY(bounds), edge), NSWidth(bounds), MAX(0, NSMaxY(bounds) - edge));
    return NSIntersectionRect(bounds, chrome);
}

// Settings are read only when they may have changed: on a refresh, or when the texture first goes in.
static void DPUpdateGrainHost(NSView *host, BOOL settings) {
    DPSidebarGrainView *grain = DPGet(host, &DPGrainViewKey);
    if (!DPSidebarGrain.on || !DPGrainHostAvailable(host)) {
        if (!grain) return;
        [grain removeFromSuperview];
        DPSet(host, &DPGrainViewKey, nil);
        return;
    }
    NSRect bounds = DPGrainHostBounds(host);
    if (!grain) {
        grain = [[DPSidebarGrainView alloc] initWithFrame:bounds];
        grain.tracksWindowActivity = YES;
        DPSet(host, &DPGrainViewKey, grain);
    }
    if (grain.superview != host) {
        [host addSubview:grain positioned:NSWindowBelow relativeTo:nil];
        settings = YES;
    }
    if (!NSEqualRects(grain.frame, bounds)) grain.frame = bounds;
    if (settings) [grain reloadSettings];
}

static void DPUpdateGrainHosts(BOOL settings) {
    for (NSView *host in DPGrainHosts) DPUpdateGrainHost(host, settings);
}

// Runs on every layout. Off, it does nothing to Dia's views unless this host still holds a texture.
void DPTrackGrainHost(NSView *host) {
    if (!DPGrainHosts) DPGrainHosts = [NSHashTable weakObjectsHashTable];
    [DPGrainHosts addObject:host];
    if (!DPSidebarGrain.on && !DPGet(host, &DPGrainViewKey)) return;
    DPUpdateGrainHosts(NO);
}

void DPRefreshSidebarGrain(void) { DPUpdateGrainHosts(YES); }

NSString *DPVerifyGrainHosts(DPPatch *patch) {
    NSMutableArray<NSView *> *hosts = [NSMutableArray new];
    for (NSView *footer in DPFindViews(DPDiaSidebarFooter))
        if (!footer.hiddenOrHasHiddenAncestor) [hosts addObject:footer.superview];
    for (NSView *strip in DPFindViews(DPDiaTabStrip))
        if (!strip.hiddenOrHasHiddenAncestor && DPGrainHostAvailable(strip)) [hosts addObject:strip];
    for (NSView *host in hosts) {
        DPSidebarGrainView *grain = DPGet(host, &DPGrainViewKey);
        BOOL installed = grain && grain.superview == host;
        if (installed != patch->on) return patch->on ? @"tab texture is missing" : @"tab texture stayed attached";
    }
    return nil;
}
