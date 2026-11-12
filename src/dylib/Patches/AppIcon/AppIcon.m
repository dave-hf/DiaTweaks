#import "AppIcon.h"
#import "Updates/Updates.h"

// macOS draws an app's icon from its bundle, once per appearance. `diapatch build` links Dia to a catalog holding every icon,
// under one fixed name, and `diapatch set-icon` repoints that name, so a switch never touches Dia's signature.
static NSUInteger DPSwitches;

static void DPAlertIconFailed(void) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Couldn’t change Dia’s icon";
    alert.informativeText = @"Dia keeps its current icon.";
    [alert runModal];
}

// A Dia built before this tweak existed has no linked catalog yet.
static void DPLinkCatalog(void) {
    DPRunCLI(@[ @"build" ], ^(NSString *output) {
        if (!output) return DPAlertIconFailed();
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Relaunch Dia to change its icon";
        alert.informativeText = @"Until then, Dia keeps its current icon.";
        [alert addButtonWithTitle:@"Relaunch"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
    });
}

static BOOL DPCatalogLinked(void) {
    return [NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"] isEqual:@"DiaChosenIcon"];
}

static void DPApplyAppIcon(DPPatch *patch) {
    if (DPTesting) return;  // the self-test flips patches without saving, and turning one off again isn't a switch
    if (!DPCatalogLinked()) {
        if (patch->on) DPLinkCatalog();
        return;
    }
    CFPreferencesAppSynchronize(CFSTR("com.diapatches"));
    NSUInteger current = ++DPSwitches;
    DPRunCLI(@[ @"set-icon" ], ^(NSString *output) {
        if (current != DPSwitches) return;  // A newer choice is on its way.
        output ? DPDrawOwnTile() : DPAlertIconFailed();
    });
}

static BOOL DPWorkspace_setIcon(NSWorkspace *self, SEL _cmd, NSImage *image, NSString *path, NSWorkspaceIconCreationOptions options) {
    if (DPAppIcon.on && [path isEqual:NSBundle.mainBundle.bundlePath]) return YES;
    return DPCallOriginal(DPWorkspace_setIcon, self, image, path, options);
}

static void DPInstallAppIcon(void) {
    DPHook("NSWorkspace", @selector(setIcon:forFile:options:), (IMP)DPWorkspace_setIcon);
    DPInstallDockTile();
    // The Dock shows the icon it last cached for Dia, which a relaunch brings back, so the chosen one is drawn again.
    DPOnLaunch(^{ if ((DPAppIcon.on || DPOwnTileInDock()) && DPCatalogLinked()) DPDrawOwnTile(); });
}

static NSString *DPVerifyAppIcon(DPPatch *patch) {
    NSString *name = NSBundle.mainBundle.infoDictionary[@"CFBundleIconName"];
    return [NSImage imageNamed:name] ? nil : @"Dia’s icon isn’t in its asset catalog";
}

static void DPAddIcon(NSMenu *menu, NSString *title, NSString *name, NSImage *image) {
    NSMenuItem *item = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
    item.representedObject = name;
    item.image = [image copy];
    item.image.size = NSMakeSize(16, 16);
}

static NSMenu *DPAppIconChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Icon"];
    NSString *section = @"Dia";
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:section]];
    DPAddIcon(menu, @"Default", @"AppIcon", [NSImage imageNamed:NSBundle.mainBundle.infoDictionary[@"DiaTweaksOwnIcon"] ?: @"AppIcon"]);
    for (NSDictionary *icon in [NSArray arrayWithContentsOfFile:DPAppSupport(@"DiaPatches/app-icons/icons.plist")]) {
        if (![icon[@"section"] isEqual:section]) [menu addItem:[NSMenuItem sectionHeaderWithTitle:(section = icon[@"section"])]];
        NSString *preview = DPAppSupport([NSString stringWithFormat:@"DiaPatches/app-icons/%@.png", icon[@"name"]]);
        DPAddIcon(menu, icon[@"title"], icon[@"name"], [[NSImage alloc] initWithContentsOfFile:preview]);
    }
    return menu;
}

// "AppIcon" stands for Dia's own icon, so turning the tweak on changes nothing until a choice is made.
DP_PATCH(DPAppIcon) {
    .key = @"appIcon",
    .order = 115,
    .title = @"App Icon",
    .detail = @"Choose a different icon for Dia. It follows the icon style you choose in System Settings.",
    .symbol = @"app.badge.fill app.badge",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .choice = @"appIconChoice",
    .defaultChoice = @"AppIcon",
    .choices = DPAppIconChoices,
    .install = DPInstallAppIcon,
    .apply = DPApplyAppIcon,
    .verify = DPVerifyAppIcon,
};
