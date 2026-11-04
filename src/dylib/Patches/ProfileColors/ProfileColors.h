// Profile Colors: any color for a profile, not just Dia's eight themes, and how strongly the window shows it.
//
// Dia saves a profile's Theme Color as one of eight theme names, so a custom color can't go into Dia's model. It's kept
// here per profile (Dia's SpaceID, as the profile pane and the sidebar's profile switcher both name it) and painted
// over the window's tint: a base layer (black at 40% in dark mode) and a gradient of the theme color at 36%, itself at
// half opacity, over macOS's see-through material. Strength raises both toward the color.
#import "StdPatch/StdPatch.h"

#define DPDiaThemePicker      "_TtC12ColorPalette15ThemePickerView"
#define DPDiaThemeOption      "_TtC12ColorPalette17ThemeOptionButton"
#define DPDiaGradientView     "_TtC5ARCUI12GradientView"
#define DPDiaBackgroundColor  "_TtC5ARCUI19BackgroundColorView"

@interface NSObject (DPProfileColorsSwift)
- (id)safeSwiftValueForKey:(NSString *)key;  // AXCoreUtilities, in every AppKit app
@end

extern DPPatch DPProfileColors;

NSColor *DPProfileColor(NSString *spaceID);       // The profile's own color, or nil for Dia's theme.
CGFloat DPProfileStrength(NSString *spaceID);     // 0 is Dia's look, 1 the strongest.
void DPSetProfileColor(NSString *spaceID, NSColor *color);
void DPSetProfileStrength(NSString *spaceID, CGFloat strength);
NSArray<NSColor *> *DPMoreProfileColors(void);    // The presets beside Dia's eight.
BOOL DPSameColor(NSColor *a, NSColor *b);

void DPRepaintProfileColors(void);  // Every window, after a setting changed.
void DPInstallProfileColorTint(void);
void DPInstallProfileColorPicker(void);
