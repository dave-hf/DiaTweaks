#import "PullRequestRepo.h"

// GitHub live folders show "author • review status" under each pull request's title, and in Created by Me the author is
// always you. This shows "hello-world #42 · Open" there instead, and moves the review status to a line of its own.
// Only the sidebar's list can make a row taller, so with tabs at the top the status stays on the repository line.

@interface NSObject (DPSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;
@end

static char DPDiaTextKey, DPCheckedKey, DPInListKey;

static id DPField(id object, NSString *key) {
    return [object respondsToSelector:@selector(safeSwiftValueForKey:)] ? [object safeSwiftValueForKey:key] : nil;
}

static NSString *DPMatch(NSString *pattern, NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = text ? [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
    return match ? [text substringWithRange:[match rangeAtIndex:match.numberOfRanges - 1]] : nil;
}

BOOL DPIsPRSubtitle(NSView *label) {
    return DPIsKind(label, DPDiaFeatheredLabel) && DPIsKind(label.superview, DPDiaTransitioningLabel);
}

// In the sidebar's list, as opposed to the tab strip at the top or a row that isn't in either yet.
static BOOL DPInTabList(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabListCollection)) view = view.superview;
    return view != nil;
}

// From the row's live item, on its TabContentController.
NSDictionary *DPPullRequestOf(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabContentView)) view = view.superview;
    id controller = DPField(DPField(view, @"viewModel"), @"delegate");
    NSString *item = [DPField(controller, @"currentlyRenderedLiveItem") description];
    if (![item containsString:@".pullRequest("]) return nil;
    NSString *repo = DPMatch(@"github\\.com/[^/\\s]+/([^/\\s)]+)/pull/[0-9]+", item), *number = DPMatch(@"github\\.com/[^\\s)]+/pull/([0-9]+)", item);
    NSString *author = DPMatch(@"author: \"([^\"]+)\"", item), *state = DPMatch(@"PullRequest\\.Status\\.([a-zA-Z]+)", item);
    NSString *tab = DPMatch(@"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", [DPField(controller, @"tabID") description]);
    if (!repo || !number || !author) return nil;
    NSString *line = [NSString stringWithFormat:@"%@ #%@", repo, number];
    state = state.length ? [[state substringToIndex:1].uppercaseString stringByAppendingString:[state substringFromIndex:1]] : @"";
    if (state.length) line = [line stringByAppendingFormat:@" · %@", state];
    return @{@"repo": line, @"state": state, @"author": author, @"tab": tab ?: @""};
}

// "author", "author •", "author • Changes Requested" and "author • Changes Requested •" (a comments icon follows a
// trailing dot). Returns the repository line, and the review status when there is one. A status that only repeats the
// state, like "Merged ✓", takes the state's place on the repository line instead.
static NSString *DPSplit(NSView *label, NSString *text, NSString **status, NSString **tab) {
    NSDictionary *pr = text.length ? DPPullRequestOf(label) : nil;
    if (!pr || ![text hasPrefix:pr[@"author"]]) return nil;
    NSString *rest = [text substringFromIndex:[pr[@"author"] length]];
    NSString *review = [rest stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" •"]];
    *tab = pr[@"tab"];
    if (!review.length) return [pr[@"repo"] stringByAppendingString:rest];
    NSString *words = [[review componentsSeparatedByCharactersInSet:NSCharacterSet.letterCharacterSet.invertedSet] componentsJoinedByString:@""];
    NSString *repo = pr[@"repo"], *state = pr[@"state"], *from = [rest substringFromIndex:[rest rangeOfString:review].location];
    if (state.length && [words caseInsensitiveCompare:state] == NSOrderedSame)
        return [[repo substringToIndex:repo.length - state.length] stringByAppendingString:from];
    if (!DPInTabList(label)) return [repo stringByAppendingString:rest];
    *status = from;
    return repo;
}

static void DPRelayoutRow(NSView *label) {
    for (NSView *view = label.superview; view; view = view.superview) {
        view.needsLayout = YES;
        if (DPIsKind(view, DPDiaTabContentView)) break;
    }
}

static void DPLabel_setStringValue(NSTextField *self, SEL _cmd, NSString *value) {
    if (!DPIsPRSubtitle(self)) return DPCallOriginal(DPLabel_setStringValue, self, value);
    NSString *status = nil, *tab = nil, *shown = DPPullRequestRepo.on && value ? DPSplit(self, value, &status, &tab) : nil;
    if (shown) DPOverride(self, &DPDiaTextKey, value, shown);
    DPSet(self, &DPCheckedKey, shown ?: value);
    DPSet(self, &DPInListKey, @(DPInTabList(self)));
    DPSetPRStatus(self, tab, status);
    DPCallOriginal(DPLabel_setStringValue, self, shown ?: value);
}

// Catches a label Dia filled in before putting it in the row, and one that moved in or out of the sidebar's list since.
static void DPLabel_layout(NSTextField *self, SEL _cmd) {
    DPCallOriginal(DPLabel_layout, self);
    if (!DPPullRequestRepo.on || !DPIsPRSubtitle(self)) return;
    BOOL moved = [DPGet(self, &DPInListKey) boolValue] != DPInTabList(self);
    if (!moved && [self.stringValue isEqual:DPGet(self, &DPCheckedKey)]) return;
    self.stringValue = DPDiaValue(self, &DPDiaTextKey, self.stringValue);
    DPRelayoutRow(self);
}

void DPRefreshPRSubtitles(void) {
    for (NSView *view in DPFindViews(DPDiaFeatheredLabel)) {
        if (!DPIsPRSubtitle(view)) continue;
        NSTextField *label = (NSTextField *)view;
        label.stringValue = DPDiaValue(label, &DPDiaTextKey, label.stringValue);
        DPRelayoutRow(label);
    }
}

void DPInstallPRSubtitles(void) {
    DPHook(DPDiaFeatheredLabel, @selector(setStringValue:), (IMP)DPLabel_setStringValue);
    DPHook(DPDiaFeatheredLabel, @selector(layout), (IMP)DPLabel_layout);
}
