#import <Foundation/Foundation.h>

// Every Dia but /Applications/Dia.app shares its bundle ID, and tools that look Dia up by it then can't tell which to use.
void DPForgetApp(NSString *app);
