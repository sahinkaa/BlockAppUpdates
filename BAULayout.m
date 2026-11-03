#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <roothide.h>
#include <notify.h>

static NSDictionary *latestLayout;
static id (*originalLoad)(id, SEL, id *);
static BOOL (*originalSave)(id, SEL, id, id *);

static NSString *backupPath(void)
{
    return jbroot(@"/var/mobile/Library/Preferences/com.sahinkaa.blockappupdates.layout.plist");
}

static void rememberLayout(id state)
{
    if (![state isKindOfClass:NSDictionary.class] || ![state count]) return;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) return;
    NSDictionary *snapshot = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:NULL];
    @synchronized (NSProcessInfo.processInfo) {
        latestLayout = snapshot;
    }
}

static id loadLayout(id store, SEL command, id *error)
{
    id state = originalLoad(store, command, error);
    NSMutableDictionary *backup = [NSMutableDictionary dictionaryWithContentsOfFile:backupPath()];
    id saved = backup[@"layout"];
    if ([backup[@"restorePending"] boolValue] && [saved isKindOfClass:NSDictionary.class] && [saved count]) {
        // Use the same model store for persistence and readback. Keep recovery
        // armed until the restored layout can be loaded from that store.
        state = saved;
        if (error) *error = nil;
        SEL save = sel_registerName("saveCurrentIconState:error:");
        if (originalSave && originalSave(store, save, saved, NULL)) {
            id persisted = originalLoad(store, command, NULL);
            if ([persisted isEqual:saved]) {
                [backup removeObjectForKey:@"restorePending"];
                backup[@"recoveryNeeded"] = @NO;
                [backup writeToFile:backupPath() atomically:YES];
            }
        }
    }
    rememberLayout(state);
    return state;
}

static BOOL saveLayout(id store, SEL command, id state, id *error)
{
    BOOL saved = originalSave(store, command, state, error);
    if (saved) rememberLayout(state);
    return saved;
}

static BOOL hasSignature(Method method, char result, unsigned count)
{
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != result) return NO;
    method_getArgumentType(method, count - 1, type, sizeof(type));
    const char *argument = type;
    while (*argument && strchr("rnNoORV", *argument)) ++argument;
    if (argument[0] != '^' || argument[1] != '@') return NO;
    if (count == 4) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

__attribute__((constructor)) static void installLayoutHooks(void)
{
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        Class cls = objc_getClass("SBDefaultIconModelStore");
        SEL load = sel_registerName("loadCurrentIconState:");
        SEL save = sel_registerName("saveCurrentIconState:error:");
        Method saveMethod = class_getInstanceMethod(cls, save);
        if (!hasSignature(class_getInstanceMethod(cls, load), '@', 3) ||
            !(hasSignature(saveMethod, 'B', 4) || hasSignature(saveMethod, 'c', 4))) return;
        MSHookMessageEx(cls, load, (IMP)loadLayout, (IMP *)&originalLoad);
        MSHookMessageEx(cls, save, (IMP)saveLayout, (IMP *)&originalSave);

        int token;
        notify_register_dispatch("com.sahinkaa.blockappupdates.capture-layout", &token,
            dispatch_get_main_queue(), ^(__unused int notification) {
                NSDictionary *state;
                @synchronized (NSProcessInfo.processInfo) {
                    state = latestLayout;
                }
                if (!state.count) return;
                [@{@"layout": state, @"recoveryNeeded": @YES,
                    @"capturedAt": @(NSProcessInfo.processInfo.systemUptime)}
                    writeToFile:backupPath() atomically:YES];
            });
    }
}
