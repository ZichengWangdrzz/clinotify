#import "CLINotifyObjCSupport.h"

BOOL CLINotifyRunCatching(void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}
