#import "Patches/ProfileColors/ProfileColors.h"

// Not "profileColors": that is the patch's own on/off key.
static NSString *const DPColorsKey = @"profileColorChoices", *const DPStrengthsKey = @"profileColorStrengths";

static NSUserDefaults *DPColorDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

static NSColor *DPColorFromHex(NSString *hex) {
    unsigned value = 0;
    if (![hex hasPrefix:@"#"] || hex.length != 7 || ![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value]) return nil;
    return [NSColor colorWithSRGBRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1];
}

static NSString *DPHexFromColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return nil;
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(rgb.redComponent * 255), (int)lround(rgb.greenComponent * 255),
                                      (int)lround(rgb.blueComponent * 255)];
}

BOOL DPSameColor(NSColor *a, NSColor *b) { return a && b && [DPHexFromColor(a) isEqual:DPHexFromColor(b)]; }

NSColor *DPProfileColor(NSString *spaceID) {
    return DPProfileColors.on && spaceID ? DPColorFromHex([DPColorDefaults() dictionaryForKey:DPColorsKey][spaceID]) : nil;
}

CGFloat DPProfileStrength(NSString *spaceID) {
    return DPProfileColors.on && spaceID ? MIN(MAX([[DPColorDefaults() dictionaryForKey:DPStrengthsKey][spaceID] doubleValue], 0), 1) : 0;
}

static void DPSetEntry(NSString *key, NSString *spaceID, id value) {
    if (!spaceID) return;
    NSMutableDictionary *all = [[DPColorDefaults() dictionaryForKey:key] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[spaceID] = value;
    [DPColorDefaults() setObject:all forKey:key];
    DPRepaintProfileColors();
}

void DPSetProfileColor(NSString *spaceID, NSColor *color) { DPSetEntry(DPColorsKey, spaceID, color ? DPHexFromColor(color) : nil); }
void DPSetProfileStrength(NSString *spaceID, CGFloat strength) { DPSetEntry(DPStrengthsKey, spaceID, strength > 0.005 ? @(strength) : nil); }

// Picked to sit apart from Dia's eight (neutral, green, blue, purple, yellow, pink, red, orange).
NSArray<NSColor *> *DPMoreProfileColors(void) {
    static NSArray *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *hex in @[ @"#0F9D8F", @"#5FD3B3", @"#22B8CF", @"#5AA9F2", @"#2B4C9B", @"#5B5BD6", @"#8E5CF0", @"#C2309A",
                                 @"#E5577A", @"#F2785C", @"#F0A202", @"#9BCB3A", @"#9A6A47", @"#5E7185", @"#3D3F45" ])
            [list addObject:DPColorFromHex(hex)];
        colors = list;
    });
    return colors;
}

static void DPInstallProfileColors(void) {
    DPInstallProfileColorTint();
    DPInstallProfileColorPicker();
}

static void DPApplyProfileColors(DPPatch *patch) { DPRepaintProfileColors(); }

DP_PATCH(DPProfileColors) {
    .key = @"profileColors",
    .order = 79,
    .defaultOn = YES,
    .title = @"Profile Colors",
    .detail = @"Give a profile any color, not just Dia’s eight, and choose how strongly the window shows it. Set them in Settings › Profiles.",
    .symbol = @"paintpalette.fill paintpalette",
    .tint = @"systemPinkColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaWindowTint, DPDiaGradientView, DPDiaBackgroundColor, DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem,
                         DPDiaProfilePane, DPDiaSettingsFormGroup, DPDiaThemePicker, DPDiaThemeOption),
    .install = DPInstallProfileColors,
    .apply = DPApplyProfileColors,
};
