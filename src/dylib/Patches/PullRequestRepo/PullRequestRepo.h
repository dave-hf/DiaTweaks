#import "StdPatch/StdPatch.h"

extern DPPatch DPPullRequestRepo;

// Subtitle.m: the line under a pull request's title.
BOOL DPIsPRSubtitle(NSView *label);
NSDictionary *DPPullRequestOf(NSView *view);  // @{repo: "hello-world #42 · Open", state, author, tab}, or nil.
void DPRefreshPRSubtitles(void);
void DPInstallPRSubtitles(void);

// Rows.m: the review status's own line, and the taller row it needs.
@interface DPPRStatusLine : NSTextField
@end
void DPSetPRStatus(NSView *subtitle, NSString *tab, NSString *status);
void DPResetPRRows(void);
void DPInstallPRRows(void);
