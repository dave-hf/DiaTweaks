// Software Update's DiaTweaks entry when it updates from a fork's git checkout instead of DiaTweaks' releases.
#import "Settings.h"

BOOL DPIsSource(NSDictionary *found);  // found[part] from DPUpdates

// The update's group: its title row with `trailing` (a button or progress bar), what's coming, any problem and a link to
// the changes. `*detail` is the line under the title, for the caller to update while it builds.
NSView *DPSourceGroup(NSDictionary *found, NSString *state, BOOL failed, BOOL installsOnQuit, NSView *trailing, NSTextField **detail);

// Rows for the Installed group: the commit, where updates come from and the checkout's folder.
NSArray<NSView *> *DPSourceInstalledRows(NSDictionary *found);

NSString *DPSourceAutoText(DPAutoLevel level);
