#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <errno.h>
#import <limits.h>
#import <notify.h>
#import <signal.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

static NSString *const BAUApplicationsPath = @"/var/containers/Bundle/Application";
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

static void BAUWaitForLaunchServicesToSettle(void)
{
    // The rebuild SPI returns after queuing database work. Keep the helper alive—and thus
    // the progress warning visible—until LaunchServices has remained queryable and stable.
    // A one-minute minimum matches the observed iOS 16 rebuild window; two minutes is a
    // safety cap for devices where no knowledge token is exposed.
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    NSString *lastToken = nil;
    NSUInteger stableSamples = 0;

    while (NSProcessInfo.processInfo.systemUptime - start < 120.0) {
        sleep(2);
        NSString *token = nil;
        if (BAUGetLaunchServicesKnowledgeToken(&token)) {
            if ([token isEqualToString:lastToken]) {
                stableSamples++;
            } else {
                lastToken = token;
                stableSamples = 0;
            }
        } else {
            stableSamples = 0;
        }

        NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - start;
        if (elapsed >= 60.0 && stableSamples >= 3) break;
        if (elapsed >= 90.0 && !lastToken) break;
    }
}

static void BAUTerminateAppStore(void)
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
        if (proc_name(pids[index], name, sizeof(name)) > 0 && strcmp(name, "AppStore") == 0) {
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
    BAUWaitForLaunchServicesToSettle();
    notify_post("com.apple.mobile.application_installed");
    BAUTerminateAppStore();
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
