#import "PullRequestRepo.h"
#import <objc/message.h>

// A pull request with a review status shows it on a third line, so its row is a line taller. Dia's list gives every tab
// the same height, so after it lays the list out, the rows below a tall one move down and the folders around it grow.

static const CGFloat DPExtra = 14, DPTabHeight = 37;
static NSMutableSet<NSString *> *DPTallTabs;
static char DPStatusKey, DPLineKey, DPAdjustedKey;

@implementation DPPRStatusLine
@end

static void DPInvalidateRows(void) {
    static BOOL scheduled;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (NSView *view in DPFindViews(DPDiaTabListCollection)) [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
    });
}

void DPSetPRStatus(NSView *subtitle, NSString *tab, NSString *status) {
    NSView *content = subtitle.superview;
    while (content && !DPIsKind(content, DPDiaTabContentView)) content = content.superview;
    DPSet(content, &DPStatusKey, status);
    content.needsLayout = YES;
    if (!tab.length || [DPTallTabs containsObject:tab] == (status != nil)) return;
    if (status) [DPTallTabs addObject:tab];
    else [DPTallTabs removeObject:tab];
    DPInvalidateRows();
}

void DPResetPRRows(void) {
    [DPTallTabs removeAllObjects];
    DPInvalidateRows();
}

// The list's items are TabList.TabListView.CollectionViewItem.tab(<tab ID>), .tabGroupHeader(…) and so on.
static NSString *DPTabAt(id source, NSIndexPath *path) {
    NSString *item = [((id (*)(id, SEL, id))objc_msgSend)(source, @selector(itemIdentifierForIndexPath:), path) description];
    NSRange open = [item rangeOfString:@".tab("];
    return open.location == NSNotFound || item.length < NSMaxRange(open) + 36 ? nil : [item substringWithRange:NSMakeRange(NSMaxRange(open), 36)];
}

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    if (!DPPullRequestRepo.on || !DPTallTabs.count) return;
    id diffable = self.collectionView.dataSource;
    Ivar ivar = class_getInstanceVariable(object_getClass(diffable), "_impl");
    id source = ivar ? object_getIvar(diffable, ivar) : nil;
    void *height = DPIvar(self, "contentHeight");  // Dia's layout hands out the attributes it keeps, so changing them changes it.
    if (![source respondsToSelector:@selector(itemIdentifierForIndexPath:)] || !height) return;
    NSArray<NSCollectionViewLayoutAttributes *> *all = [self layoutAttributesForElementsInRect:NSMakeRect(-1e5, -1e5, 2e5, 1e7)];
    NSMutableArray<NSCollectionViewLayoutAttributes *> *tall = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && [DPTallTabs containsObject:DPTabAt(source, a.indexPath)]) [tall addObject:a];
    // A prepare that kept the last geometry still has our heights in it.
    NSArray *last = DPGet(self, &DPAdjustedKey);
    if (!tall.count || (last[0] == tall[0] && NSEqualRects([last[1] rectValue], tall[0].frame))) return;
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in tall) [rows addObject:[NSValue valueWithRect:a.frame]];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            if (NSMinY(a.frame) >= NSMaxY(row) - 0.5) frame.origin.y += DPExtra;
            else if (NSMinY(a.frame) <= NSMinY(row) + 0.5 && NSMaxY(a.frame) >= NSMaxY(row) - 0.5) frame.size.height += DPExtra;  // it, or a folder around it
        }
        a.frame = frame;
    }
    *(double *)height += DPExtra * rows.count;
    DPSet(self, &DPAdjustedKey, @[tall[0], [NSValue valueWithRect:tall[0].frame]]);
}

static NSView *DPPart(NSView *content, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(content), name);
    id part = ivar ? object_getIvar(content, ivar) : nil;
    return [part isKindOfClass:NSView.class] ? part : nil;
}

// Title, repository and status, centred together in the taller row. The comments icon follows the status.
static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    NSString *status = DPPullRequestRepo.on ? DPGet(self, &DPStatusKey) : nil;
    NSView *title = DPPart(self, "$__lazy_storage_$_titleView"), *subtitle = DPPart(self, "subtitleView"), *icon = DPPart(self, "subtitleIconView");
    NSTextField *line = DPGet(self, &DPLineKey), *source = (NSTextField *)DPSubview(subtitle, DPDiaFeatheredLabel);
    BOOL tall = status && title && source && NSHeight(self.bounds) >= DPTabHeight + DPExtra - 1;
    line.hidden = !tall;
    if (!tall) return;
    if (!line) DPSet(self, &DPLineKey, line = [DPPRStatusLine labelWithString:@""]);
    if (line.superview != self) [self addSubview:line];
    line.font = source.font;
    line.textColor = source.textColor;
    line.lineBreakMode = NSLineBreakByTruncatingTail;
    line.stringValue = status;
    CGFloat lineHeight = NSHeight(subtitle.frame), bottom = round((NSHeight(self.bounds) - NSHeight(title.frame) - 2 * lineHeight) / 2);
    // The whole width, so it only cuts off what doesn't fit. The icon goes after the text.
    CGFloat x = NSMinX(subtitle.frame), width = NSWidth(self.bounds) - x - 8;
    CGFloat text = ceil([status sizeWithAttributes:@{NSFontAttributeName: line.font ?: [NSFont systemFontOfSize:11]}].width);
    line.frame = NSMakeRect(x, bottom, width, lineHeight);
    [subtitle setFrameOrigin:NSMakePoint(x, bottom + lineHeight)];
    [title setFrameOrigin:NSMakePoint(NSMinX(title.frame), bottom + 2 * lineHeight)];
    if (icon && !icon.hidden) [icon setFrameOrigin:NSMakePoint(x + MIN(text, width) + 5, bottom + (lineHeight - NSHeight(icon.frame)) / 2)];
}

void DPInstallPRRows(void) {
    DPTallTabs = [NSMutableSet new];
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
}
