#import <Foundation/Foundation.h>

// Gives the Dia being built at `app` one catalog holding Dia's assets and every icon in `home`/app-icons, kept outside the bundle
// so `DPSwitchIcon` can change the icon without touching the signature. Returns what happened for the log; a problem leaves
// Dia's own catalog in place and never stops a build. `installed` is the Dia still in use, whose catalog must survive.
NSString *DPPrepareIcons(NSString *app, NSString *installed, NSString *home);

// Points Dia at the icon chosen in the App Icon tweak. nil on success, else what went wrong.
NSString *DPSwitchIcon(NSString *app, NSString *home);
