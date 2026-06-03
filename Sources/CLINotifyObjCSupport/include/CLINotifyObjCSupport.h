#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, catching any Objective-C `NSException` it raises.
///
/// Some AppKit/Foundation APIs (notably `UNUserNotificationCenter`) raise uncatchable-in-Swift
/// `NSException`s on unsigned/improperly-bundled processes. Wrapping the call here lets the daemon
/// degrade gracefully instead of aborting. Returns `YES` if the block completed without raising,
/// `NO` if an exception was caught.
BOOL CLINotifyRunCatching(void (^block)(void));

NS_ASSUME_NONNULL_END
