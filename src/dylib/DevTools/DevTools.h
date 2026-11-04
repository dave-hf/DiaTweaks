// Tools for writing patches, on with `defaults write com.diapatches devTools -bool YES` and a relaunch of Dia.
#import "StdPatch/StdPatch.h"

void DPInstallDevTools(void);
void DPInstallInspect(void);  // Inspect.m: script commands for classes and Swift properties.
NSString *DPDescribeViews(NSView *root);  // One line per view: class, frame, label, rounded corners, and whether it's hidden.
