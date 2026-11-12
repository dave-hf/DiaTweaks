#import "StdPatch/Hide.h"

extern DPPatch DPTurnOffAI;

// Settings rows and shortcuts named after one of Dia's AI features.
BOOL DPIsAITitle(NSString *title);

// The height of the suggestions Turn Off AI has hidden, which Dia still counts in the command bar.
CGFloat DPHiddenSuggestionsHeight(NSView *suggestions);

void DPInstallAIRows(void);
void DPApplyAIRows(void);
