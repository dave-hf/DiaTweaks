#import "PullRequestRepo.h"

static void DPApplyPullRequestRepo(DPPatch *patch) {
    DPRefreshPRSubtitles();
    if (!patch->on) DPResetPRRows();
}

// On, no pull request shows its author. Off, none shows its repository or a status line of ours.
static NSString *DPVerifyPullRequestRepo(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaFeatheredLabel)) {
        if (!DPIsPRSubtitle(view) || view.hiddenOrHasHiddenAncestor) continue;
        NSDictionary *pr = DPPullRequestOf(view);
        NSString *text = ((NSTextField *)view).stringValue;
        if (!pr) continue;
        if (patch->on && [text hasPrefix:pr[@"author"]]) return @"a pull request still shows its author";
        if (!patch->on && [text hasPrefix:pr[@"repo"]]) return @"a pull request still shows its repository";
    }
    for (NSView *view in DPFindViews(DPDiaTabContentView))
        for (NSView *sub in view.subviews)
            if (!patch->on && [sub isKindOfClass:DPPRStatusLine.class] && !sub.hidden) return @"a status line still shows";
    return nil;
}

static void DPInstallPullRequestRepo(void) {
    DPInstallPRSubtitles();
    DPInstallPRRows();
}

DP_PATCH(DPPullRequestRepo) {
    .key = @"pullRequestRepo",
    .order = 79,
    .title = @"Show Repo on Pull Requests",
    .detail = @"In GitHub live folders, show each pull request's repository, number and state under its title instead of the author, with the review status on a line below (beside it with tabs at the top).",
    .symbol = @"arrow.triangle.pull",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabContentView, DPDiaFeatheredLabel, DPDiaTransitioningLabel, DPDiaTabListLayout, DPDiaTabListCollection),
    .install = DPInstallPullRequestRepo,
    .apply = DPApplyPullRequestRepo,
    .verify = DPVerifyPullRequestRepo,
};
