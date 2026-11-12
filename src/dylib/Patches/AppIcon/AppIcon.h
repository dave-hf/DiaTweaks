#import "StdPatch/StdPatch.h"

extern DPPatch DPAppIcon;

NSImage *DPClearTile(NSImage *icon, BOOL dark);
void DPDrawOwnTile(void);  // Until the next icon style change, when the Dock takes its tile back.
BOOL DPOwnTileInDock(void);
void DPInstallDockTile(void);
