#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <signal.h>
#import <spawn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

static NSString *const BAUApplicationsPath = @"/var/containers/Bundle/Application";
static NSString *const BAUHelperInstallSuffix = @"/Library/PreferenceBundles/";
static NSString *const BAUMetadataName = @"iTunesMetadata.plist";
static NSString *const BAUBlockedMetadataName = @"iTunesMetadata_blocked.plist";

extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);
static const uint32_t BAUProcAllPIDs = 1;

static BOOL BAUHasMarker(NSString *path)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    return [manager fileExistsAtPath:[path stringByAppendingPathComponent:@"_TrollStore"]] ||
           [manager fileExistsAtPath:[path stringByAppendingPathComponent:@"_TrollStoreLite"]];
}

static NSString *BAUAppBundlePath(NSString *containerPath)
{
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:containerPath error:nil] ?: @[];
    for (NSString *entry in entries) {
        if ([entry.pathExtension.lowercaseString isEqualToString:@"app"]) {
            return [containerPath stringByAppendingPathComponent:entry];
        }
    }
    return nil;
}

static NSString *BAUValidatedContainerPath(NSString *requestedPath, NSString **errorMessage)
{
    char resolvedBuffer[PATH_MAX];
    if (!realpath(requestedPath.fileSystemRepresentation, resolvedBuffer)) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not resolve the application container: %s", strerror(errno)];
        return nil;
    }

    NSString *containerPath = [NSString stringWithUTF8String:resolvedBuffer];
    NSString *parentPath = containerPath.stringByDeletingLastPathComponent.stringByStandardizingPath;
    if (![parentPath isEqualToString:BAUApplicationsPath] || BAUHasMarker(containerPath)) {
        if (errorMessage) *errorMessage = @"The requested path is not an eligible App Store container.";
        return nil;
    }

    NSString *bundlePath = BAUAppBundlePath(containerPath);
    if (!bundlePath || BAUHasMarker(bundlePath)) {
        if (errorMessage) *errorMessage = @"No eligible application bundle was found.";
        return nil;
    }
    return containerPath;
}

static void BAURebuildLaunchServicesDatabases(void)
{
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL rebuildSelector = NSSelectorFromString(@"_LSPrivateRebuildApplicationDatabasesForSystemApps:internal:user:");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSelector]) return;

    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSelector);
    if (!workspace || ![workspace respondsToSelector:rebuildSelector]) return;

    ((void (*)(id, SEL, BOOL, BOOL, BOOL))objc_msgSend)(workspace, rebuildSelector, YES, YES, YES);
}

static BOOL BAUGetLaunchServicesKnowledgeToken(NSString **tokenOut)
{
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL knowledgeSelector = NSSelectorFromString(@"getKnowledgeUUID:andSequenceNumber:");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSelector]) return NO;

    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSelector);
    if (!workspace || ![workspace respondsToSelector:knowledgeSelector]) return NO;

    __autoreleasing id knowledgeUUID = nil;
    uint64_t sequenceNumber = 0;
    ((void (*)(id, SEL, id *, uint64_t *))objc_msgSend)(workspace, knowledgeSelector, &knowledgeUUID, &sequenceNumber);
    if (!knowledgeUUID) return NO;
    if (tokenOut) *tokenOut = [NSString stringWithFormat:@"%@-%llu", knowledgeUUID, sequenceNumber];
    return YES;
}

static uint64_t BAURegisteredStoreItemID(NSString *bundleIdentifier)
{
    @autoreleasepool {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return 0;

        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, bundleIdentifier);
        if (![proxy respondsToSelector:NSSelectorFromString(@"itemID")]) return 0;
        id itemID = [proxy valueForKey:@"itemID"];
        return [itemID respondsToSelector:@selector(unsignedLongLongValue)] ? [itemID unsignedLongLongValue] : 0;
    }
}

static BOOL BAURegistrationsMatch(NSArray<NSDictionary *> *expectations)
{
    for (NSDictionary *expectation in expectations) {
        uint64_t registeredItemID = BAURegisteredStoreItemID(expectation[@"bundleIdentifier"]);
        uint64_t expectedItemID = [expectation[@"itemID"] unsignedLongLongValue];
        if (registeredItemID != expectedItemID) return NO;
    }
    return YES;
}

static void BAUWaitForLaunchServicesToSettle(NSArray<NSDictionary *> *expectations)
{
    // On iOS 15–26 the rebuild SPI is synchronous (about 12–23 seconds), and the changed apps
    // already carry their new store item ID when it returns. Finish as soon as every changed
    // app reflects its new state and the database has stopped changing for a moment; the cap
    // only matters if a future iOS release turns the rebuild asynchronous again.
    static const NSTimeInterval BAUPollInterval = 0.25;
    static const NSTimeInterval BAUStableDuration = 1.0;
    static const NSTimeInterval BAUMaximumWait = 60.0;

    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval stableSince = start;
    NSString *lastToken = nil;

    while (NSProcessInfo.processInfo.systemUptime - start < BAUMaximumWait) {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        NSString *token = nil;
        BAUGetLaunchServicesKnowledgeToken(&token);
        if (!BAURegistrationsMatch(expectations) || (token && ![token isEqualToString:lastToken])) {
            stableSince = now;
        } else if (now - stableSince >= BAUStableDuration) {
            return;
        }
        lastToken = token;
        usleep((useconds_t)(BAUPollInterval * 1000000));
    }
}

static NSString *BAUJailbreakRootPath(void)
{
    // The helper is installed below <jbroot>/Library/PreferenceBundles, so its own location
    // yields the jailbreak root on rootless (/var/jb) and roothide (.jbroot-*) alike.
    char executableBuffer[PATH_MAX];
    uint32_t size = sizeof(executableBuffer);
    if (_NSGetExecutablePath(executableBuffer, &size) != 0) return nil;

    char resolvedBuffer[PATH_MAX];
    if (!realpath(executableBuffer, resolvedBuffer)) return nil;

    NSString *executablePath = [NSString stringWithUTF8String:resolvedBuffer];
    NSRange range = [executablePath rangeOfString:BAUHelperInstallSuffix options:NSBackwardsSearch];
    if (range.location == NSNotFound) return nil;
    return [executablePath substringToIndex:range.location];
}

static BOOL BAUIsExecutable(NSString *path)
{
    return path && access(path.fileSystemRepresentation, X_OK) == 0;
}

static int BAURunTool(NSString *path, NSArray<NSString *> *toolArguments, NSTimeInterval timeout)
{
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    char **arguments = calloc(toolArguments.count + 2, sizeof(char *));
    arguments[0] = (char *)path.fileSystemRepresentation;
    for (NSUInteger index = 0; index < toolArguments.count; index++) {
        arguments[index + 1] = (char *)toolArguments[index].UTF8String;
    }

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, arguments[0], &actions, NULL, arguments, environ);
    free(arguments);
    posix_spawn_file_actions_destroy(&actions);
    if (spawnResult != 0) return -1;

    // A stuck registration tool must not leave the Settings progress alert up forever.
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    int status = 0;
    while (YES) {
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) break;
        if (result < 0 && errno != EINTR) return -1;
        if (NSProcessInfo.processInfo.systemUptime - start >= timeout) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            return -1;
        }
        usleep(100000);
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static NSArray<NSString *> *BAUApplicationBundlesInDirectory(NSString *directoryPath)
{
    NSMutableArray<NSString *> *bundles = [NSMutableArray array];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directoryPath error:nil] ?: @[];
    for (NSString *entry in entries) {
        if ([entry.pathExtension.lowercaseString isEqualToString:@"app"]) {
            [bundles addObject:[directoryPath stringByAppendingPathComponent:entry]];
        }
    }
    return bundles;
}

static void BAURestoreThirdPartyRegistrations(void)
{
    // Rebuilding the LaunchServices databases only re-registers apps known to installd.
    // Jailbreak apps, TrollStore and TrollStore Lite register themselves directly with
    // LaunchServices, so they lose their records (missing labels, apps that no longer launch
    // or run letterboxed). Re-register them the same way uicache and "Refresh App Registrations" do.
    NSString *jailbreakRoot = BAUJailbreakRootPath();
    NSString *jailbreakApplicationsPath = [jailbreakRoot stringByAppendingPathComponent:@"Applications"];

    NSString *uicachePath = [jailbreakRoot stringByAppendingPathComponent:@"usr/bin/uicache"];
    if (jailbreakRoot && BAUIsExecutable(uicachePath)) {
        for (NSString *bundlePath in BAUApplicationBundlesInDirectory(jailbreakApplicationsPath)) {
            BAURunTool(uicachePath, @[@"-p", bundlePath], 30.0);
        }
    }

    NSArray<NSString *> *containers = [NSFileManager.defaultManager contentsOfDirectoryAtPath:BAUApplicationsPath error:nil] ?: @[];
    for (NSString *container in containers) {
        NSString *trollStoreHelperPath = [BAUApplicationsPath stringByAppendingPathComponent:
            [container stringByAppendingPathComponent:@"TrollStore.app/trollstorehelper"]];
        if (BAUIsExecutable(trollStoreHelperPath)) {
            BAURunTool(trollStoreHelperPath, @[@"refresh"], 60.0);
        }
    }

    NSString *trollStoreLiteHelperPath = [jailbreakApplicationsPath stringByAppendingPathComponent:@"TrollStoreLite.app/trollstorehelper"];
    if (jailbreakRoot && BAUIsExecutable(trollStoreLiteHelperPath)) {
        BAURunTool(trollStoreLiteHelperPath, @[@"refresh"], 60.0);
    }
}

static void BAUTerminateAppStoreProcesses(void)
{
    int requiredBytes = proc_listpids(BAUProcAllPIDs, 0, NULL, 0);
    if (requiredBytes <= 0) return;

    size_t capacity = (size_t)requiredBytes + (sizeof(pid_t) * 32);
    pid_t *pids = calloc(1, capacity);
    if (!pids) return;

    int receivedBytes = proc_listpids(BAUProcAllPIDs, 0, pids, (int)capacity);
    int count = receivedBytes > 0 ? receivedBytes / (int)sizeof(pid_t) : 0;
    for (int index = 0; index < count; index++) {
        if (pids[index] <= 1 || pids[index] == getpid()) continue;
        char name[256] = {0};
        // appstored caches the update list independently of the App Store UI; launchd restarts it on demand.
        if (proc_name(pids[index], name, sizeof(name)) > 0 &&
            (strcmp(name, "AppStore") == 0 || strcmp(name, "appstored") == 0)) {
            kill(pids[index], SIGTERM);
        }
    }
    free(pids);
}

static int BAUCleanupReinstalledContainer(NSString *requestedPath)
{
    NSString *validationError = nil;
    NSString *containerPath = BAUValidatedContainerPath(requestedPath, &validationError);
    if (!containerPath) {
        fprintf(stderr, "%s", validationError.UTF8String);
        return 6;
    }

    NSString *normalPath = [containerPath stringByAppendingPathComponent:BAUMetadataName];
    NSString *blockedPath = [containerPath stringByAppendingPathComponent:BAUBlockedMetadataName];
    if (access(normalPath.fileSystemRepresentation, F_OK) != 0 || access(blockedPath.fileSystemRepresentation, F_OK) != 0) {
        fprintf(stderr, "The container no longer has both metadata files.");
        return 7;
    }
    if (unlink(blockedPath.fileSystemRepresentation) != 0) {
        fprintf(stderr, "Could not remove stale blocked metadata: %s", strerror(errno));
        return 8;
    }
    return 0;
}

static int BAUCommitChanges(NSArray<NSString *> *arguments)
{
    if (arguments.count == 0 || arguments.count % 2 != 0) {
        fprintf(stderr, "The commit request is malformed.");
        return 4;
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *changes = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *expectations = [NSMutableArray array];
    for (NSUInteger index = 0; index < arguments.count; index += 2) {
        NSString *operation = arguments[index];
        BOOL shouldBlock = [operation isEqualToString:@"block"];
        if (!shouldBlock && ![operation isEqualToString:@"unblock"]) {
            fprintf(stderr, "Unknown operation.");
            return 4;
        }

        NSString *validationError = nil;
        NSString *containerPath = BAUValidatedContainerPath(arguments[index + 1], &validationError);
        if (!containerPath) {
            fprintf(stderr, "%s", validationError.UTF8String);
            return 6;
        }

        NSString *sourceName = shouldBlock ? BAUMetadataName : BAUBlockedMetadataName;
        NSString *destinationName = shouldBlock ? BAUBlockedMetadataName : BAUMetadataName;
        NSString *sourcePath = [containerPath stringByAppendingPathComponent:sourceName];
        NSString *destinationPath = [containerPath stringByAppendingPathComponent:destinationName];
        if (access(sourcePath.fileSystemRepresentation, F_OK) != 0) {
            fprintf(stderr, "A source metadata file no longer exists.");
            return 8;
        }
        if (access(destinationPath.fileSystemRepresentation, F_OK) == 0) {
            fprintf(stderr, "Both metadata filenames exist; reopen the pane so it can clean up the reinstalled app.");
            return 9;
        }
        [changes addObject:@{@"source": sourcePath, @"destination": destinationPath}];

        // A blocked app has no store metadata, so LaunchServices reports item ID 0 for it.
        NSString *infoPath = [BAUAppBundlePath(containerPath) stringByAppendingPathComponent:@"Info.plist"];
        NSString *bundleIdentifier = [NSDictionary dictionaryWithContentsOfFile:infoPath][@"CFBundleIdentifier"];
        id metadataItemID = [NSDictionary dictionaryWithContentsOfFile:sourcePath][@"itemId"];
        if ([bundleIdentifier isKindOfClass:NSString.class] && [metadataItemID respondsToSelector:@selector(unsignedLongLongValue)]) {
            [expectations addObject:@{
                @"bundleIdentifier": bundleIdentifier,
                @"itemID": @(shouldBlock ? 0 : [metadataItemID unsignedLongLongValue])
            }];
        }
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *applied = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *change in changes) {
        if (rename(change[@"source"].fileSystemRepresentation, change[@"destination"].fileSystemRepresentation) != 0) {
            for (NSDictionary<NSString *, NSString *> *rollback in applied.reverseObjectEnumerator) {
                rename(rollback[@"destination"].fileSystemRepresentation, rollback[@"source"].fileSystemRepresentation);
            }
            fprintf(stderr, "Could not rename a metadata file: %s", strerror(errno));
            return 10;
        }
        [applied addObject:change];
    }

    // One expensive refresh covers every rename in this commit.
    BAURebuildLaunchServicesDatabases();
    BAUWaitForLaunchServicesToSettle(expectations);
    BAURestoreThirdPartyRegistrations();
    notify_post("com.apple.mobile.application_installed");
    BAUTerminateAppStoreProcesses();
    return 0;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "Invalid arguments.");
            return 2;
        }
        if (geteuid() != 0) {
            fprintf(stderr, "The privileged helper did not start as root.");
            return 3;
        }
        if (setuid(0) != 0 || getuid() != 0) {
            fprintf(stderr, "The privileged helper could not make its root identity permanent.");
            return 3;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"cleanup"] && argc == 3) {
            return BAUCleanupReinstalledContainer([NSString stringWithUTF8String:argv[2]]);
        }
        if ([command isEqualToString:@"commit"]) {
            NSMutableArray<NSString *> *arguments = [NSMutableArray array];
            for (int index = 2; index < argc; index++) {
                [arguments addObject:[NSString stringWithUTF8String:argv[index]]];
            }
            return BAUCommitChanges(arguments);
        }

        fprintf(stderr, "Unknown command.");
        return 4;
    }
}
