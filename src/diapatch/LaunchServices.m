#import "LaunchServices.h"

// Launch Services registers an app when it is launched or moved into place, so callers forget it after each.
void DPForgetApp(NSString *app) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"];
    task.arguments = @[ @"-u", app ];
    task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;  // it complains about apps it never registered
    if ([task launchAndReturnError:NULL]) [task waitUntilExit];
}
