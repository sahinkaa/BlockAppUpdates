#import "BAURootListController.h"
#import "BAUApp.h"

#import <UIKit/UIKit.h>
#import <roothide.h>
#import <errno.h>
#import <spawn.h>
#import <stdlib.h>
#import <sys/wait.h>

extern char **environ;

static NSString *const BAUApplicationsPath = @"/var/containers/Bundle/Application";
static NSString *const BAUMetadataName = @"iTunesMetadata.plist";
static NSString *const BAUBlockedMetadataName = @"iTunesMetadata_blocked.plist";

@interface UIImage (BAUPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                                format:(NSInteger)format
                                                 scale:(CGFloat)scale;
@end

@interface BAURootListController ()
@property (nonatomic, copy) NSArray<BAUApp *> *blockedApps;
@property (nonatomic, copy) NSArray<BAUApp *> *availableApps;
@property (nonatomic, strong) UITableView *applicationsTableView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pendingStates;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, strong) UIBarButtonItem *commitButton;
@property (nonatomic, strong) UIBarButtonItem *layoutButton;
@end

@implementation BAURootListController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Block App Updates";
    self.pendingStates = [NSMutableDictionary dictionary];
    self.iconCache = [[NSCache alloc] init];
    self.iconCache.countLimit = 128;

    self.applicationsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.applicationsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.applicationsTableView.dataSource = self;
    self.applicationsTableView.delegate = self;
    self.applicationsTableView.rowHeight = 56.0;
    self.applicationsTableView.alwaysBounceVertical = YES;
    [self.view addSubview:self.applicationsTableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.applicationsTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.applicationsTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.applicationsTableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.applicationsTableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self configureHeaderView];

    self.commitButton = [[UIBarButtonItem alloc] initWithTitle:@"Commit"
                                                         style:UIBarButtonItemStyleDone
                                                        target:self
                                                        action:@selector(commitButtonPressed)];
    self.layoutButton = [[UIBarButtonItem alloc] initWithTitle:@"Restore Icon Layout"
        style:UIBarButtonItemStylePlain target:self action:@selector(offerLayoutRestore)];
    self.navigationItem.rightBarButtonItems = @[self.commitButton, self.layoutButton];
    [self updateLayoutButton];
    [self updateCommitButton];
    [self reloadApplications];
}

- (void)configureHeaderView
{
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 166.0)];

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    UIImage *icon = [UIImage imageNamed:@"BlockAppUpdates" inBundle:bundle compatibleWithTraitCollection:nil];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 15.0;
    iconView.layer.masksToBounds = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Block App Updates";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];

    UILabel *developerLabel = [[UILabel alloc] init];
    developerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    developerLabel.textAlignment = NSTextAlignmentCenter;
    developerLabel.textColor = UIColor.secondaryLabelColor;
    NSMutableAttributedString *developer = [[NSMutableAttributedString alloc]
        initWithString:@"by sahinkaa"
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular]}];
    [developer addAttribute:NSFontAttributeName
                      value:[UIFont systemFontOfSize:15.0 weight:UIFontWeightBold]
                      range:NSMakeRange(3, @"sahinkaa".length)];
    developerLabel.attributedText = developer;

    [header addSubview:iconView];
    [header addSubview:titleLabel];
    [header addSubview:developerLabel];
    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [iconView.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:72.0],
        [iconView.heightAnchor constraintEqualToConstant:72.0],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:16.0],
        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [developerLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [developerLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor]
    ]];
    self.applicationsTableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadApplications];
}

- (void)reloadApplications
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *containers = [manager contentsOfDirectoryAtPath:BAUApplicationsPath error:nil] ?: @[];
    NSMutableArray<BAUApp *> *blocked = [NSMutableArray array];
    NSMutableArray<BAUApp *> *available = [NSMutableArray array];
    NSMutableSet<NSString *> *visibleContainerPaths = [NSMutableSet set];

    for (NSString *containerName in containers) {
        NSString *containerPath = [BAUApplicationsPath stringByAppendingPathComponent:containerName];
        BOOL hasMetadata = [manager fileExistsAtPath:[containerPath stringByAppendingPathComponent:BAUMetadataName]];
        BOOL hasBlockedMetadata = [manager fileExistsAtPath:[containerPath stringByAppendingPathComponent:BAUBlockedMetadataName]];
        if (!hasMetadata && !hasBlockedMetadata) continue;
        if ([self pathHasTrollStoreMarker:containerPath manager:manager]) continue;

        NSArray<NSString *> *entries = [manager contentsOfDirectoryAtPath:containerPath error:nil] ?: @[];
        NSString *bundlePath = nil;
        for (NSString *entry in entries) {
            if ([entry.pathExtension.lowercaseString isEqualToString:@"app"]) {
                bundlePath = [containerPath stringByAppendingPathComponent:entry];
                break;
            }
        }
        if (!bundlePath || [self pathHasTrollStoreMarker:bundlePath manager:manager]) continue;

        // A normal metadata file appearing beside our blocked copy means the App Store app
        // was reinstalled. Remove the stale marker and treat it as unblocked.
        if (hasMetadata && hasBlockedMetadata) {
            NSString *cleanupError = nil;
            [self runHelperArguments:@[@"cleanup", containerPath] errorMessage:&cleanupError];
            hasBlockedMetadata = NO;
            [self.pendingStates removeObjectForKey:containerPath];
        }

        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
        NSString *bundleIdentifier = info[@"CFBundleIdentifier"];
        if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0) continue;

        // Some apps ship an empty CFBundleDisplayName, so fall through to the next non-empty name.
        NSString *name = bundleIdentifier;
        for (NSString *key in @[@"CFBundleDisplayName", @"CFBundleName"]) {
            NSString *candidate = info[key];
            if ([candidate isKindOfClass:NSString.class] && candidate.length > 0) {
                name = candidate;
                break;
            }
        }

        NSString *version = info[@"CFBundleShortVersionString"];
        if (![version isKindOfClass:NSString.class] || version.length == 0) version = info[@"CFBundleVersion"];
        if (![version isKindOfClass:NSString.class] || version.length == 0) version = nil;

        BAUApp *app = [[BAUApp alloc] initWithName:name
                                  bundleIdentifier:bundleIdentifier
                                      containerPath:containerPath
                                         bundlePath:bundlePath
                                            version:version
                                            blocked:hasBlockedMetadata];
        [(app.isBlocked ? blocked : available) addObject:app];
        [visibleContainerPaths addObject:containerPath];
    }

    for (NSString *pendingPath in self.pendingStates.allKeys.copy) {
        if (![visibleContainerPaths containsObject:pendingPath]) {
            [self.pendingStates removeObjectForKey:pendingPath];
        }
    }

    NSComparator comparator = ^NSComparisonResult(BAUApp *left, BAUApp *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    };
    self.blockedApps = [blocked sortedArrayUsingComparator:comparator];
    self.availableApps = [available sortedArrayUsingComparator:comparator];
    [self.applicationsTableView reloadData];
    [self updateCommitButton];
}

- (BOOL)pathHasTrollStoreMarker:(NSString *)path manager:(NSFileManager *)manager
{
    return [manager fileExistsAtPath:[path stringByAppendingPathComponent:@"_TrollStore"]] ||
           [manager fileExistsAtPath:[path stringByAppendingPathComponent:@"_TrollStoreLite"]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? self.blockedApps.count : self.availableApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"Blocked Updates" : @"Applications";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0 && self.blockedApps.count == 0) return @"No app updates are currently blocked.";
    if (section == 1 && self.availableApps.count == 0) return @"No eligible App Store apps were found.";
    return nil;
}

- (BAUApp *)appAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section == 0 ? self.blockedApps[indexPath.row] : self.availableApps[indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"BAUAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    BAUApp *app = [self appAtIndexPath:indexPath];
    NSNumber *pendingState = self.pendingStates[app.containerPath];
    cell.textLabel.text = app.version
        ? [NSString stringWithFormat:@"%@ (%@)", app.name, app.version]
        : app.name;
    if (pendingState) {
        NSString *pendingLabel = pendingState.boolValue ? @"Will block" : @"Will unblock";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app.bundleIdentifier, pendingLabel];
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.detailTextLabel.text = app.bundleIdentifier;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    cell.imageView.image = [self iconForApp:app];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.layer.cornerRadius = 6.5;
    cell.imageView.layer.masksToBounds = YES;
    return cell;
}

- (UIImage *)iconForApp:(BAUApp *)app
{
    UIImage *cachedIcon = [self.iconCache objectForKey:app.bundleIdentifier];
    if (cachedIcon) return cachedIcon;

    UIImage *sourceIcon = [UIImage _applicationIconImageForBundleIdentifier:app.bundleIdentifier
                                                                       format:2
                                                                        scale:UIScreen.mainScreen.scale];
    if (!sourceIcon) return nil;

    CGSize size = CGSizeMake(29.0, 29.0);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = UIScreen.mainScreen.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *fittedIcon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [sourceIcon drawInRect:(CGRect){ .origin = CGPointZero, .size = size }];
    }];
    [self.iconCache setObject:fittedIcon forKey:app.bundleIdentifier];
    return fittedIcon;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BAUApp *app = [self appAtIndexPath:indexPath];
    NSNumber *pendingState = self.pendingStates[app.containerPath];
    BOOL currentDesiredState = pendingState ? pendingState.boolValue : app.isBlocked;
    BOOL newDesiredState = !currentDesiredState;

    if (newDesiredState == app.isBlocked) {
        [self.pendingStates removeObjectForKey:app.containerPath];
    } else {
        self.pendingStates[app.containerPath] = @(newDesiredState);
    }
    [self.applicationsTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateCommitButton];
}

- (void)updateCommitButton
{
    self.commitButton.enabled = self.pendingStates.count > 0;
    self.commitButton.title = self.pendingStates.count > 0
        ? [NSString stringWithFormat:@"Commit (%lu)", (unsigned long)self.pendingStates.count]
        : @"Commit";
}

static NSString *BAULayoutBackupPath(void)
{
    return jbroot(@"/var/mobile/Library/Preferences/com.sahinkaa.blockappupdates.layout.plist");
}

- (void)updateLayoutButton
{
    NSDictionary *backup = [NSDictionary dictionaryWithContentsOfFile:BAULayoutBackupPath()];
    BOOL recoveryNeeded = [backup[@"recoveryNeeded"] boolValue];
    self.navigationItem.rightBarButtonItems = recoveryNeeded
        ? @[self.commitButton, self.layoutButton] : @[self.commitButton];
    self.layoutButton.enabled = recoveryNeeded;
}

- (void)offerLayoutRestore
{
    NSDictionary *backup = [NSDictionary dictionaryWithContentsOfFile:BAULayoutBackupPath()];
    if (![backup[@"layout"] isKindOfClass:NSDictionary.class] || ![backup[@"layout"] count]) {
        [self showMessageWithTitle:@"Layout Unavailable" message:@"There is no valid saved Home Screen layout."];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore Home Screen Layout?"
        message:@"Make sure your jailbreak apps are visible. Restoring replaces the current layout with the saved copy and resprings."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring to Restore Layout" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
            [self restoreSavedLayoutAndRespring];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreSavedLayoutAndRespring
{
    NSMutableDictionary *backup = [NSMutableDictionary dictionaryWithContentsOfFile:BAULayoutBackupPath()];
    if (![backup[@"layout"] isKindOfClass:NSDictionary.class] || ![backup[@"layout"] count]) {
        [self showMessageWithTitle:@"Restore Unavailable" message:@"There is no valid saved layout."];
        return;
    }

    self.layoutButton.enabled = NO;
    self.commitButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        if (![self runHelperArguments:@[@"respring-layout"] errorMessage:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateLayoutButton];
                [self updateCommitButton];
                [self showMessageWithTitle:@"Respring Needed" message:error];
            });
        }
    });
}

- (void)commitButtonPressed
{
    NSUInteger count = self.pendingStates.count;
    if (count == 0) return;

    if (self.layoutButton.enabled) {
        [self showMessageWithTitle:@"Restore Icon Layout First"
            message:@"Recover the previous layout before starting another Commit."];
        return;
    }

    NSUInteger blockCount = 0;
    NSUInteger unblockCount = 0;
    for (NSNumber *state in self.pendingStates.allValues) {
        if (state.boolValue) blockCount++;
        else unblockCount++;
    }

    NSString *summary = nil;
    if (blockCount > 0 && unblockCount > 0) {
        summary = [NSString stringWithFormat:@"Updates will be blocked for %lu %@ and allowed again for %lu %@.",
            (unsigned long)blockCount, blockCount == 1 ? @"app" : @"apps",
            (unsigned long)unblockCount, unblockCount == 1 ? @"app" : @"apps"];
    } else if (blockCount > 0) {
        summary = [NSString stringWithFormat:@"Updates will be blocked for %lu %@.",
            (unsigned long)blockCount, blockCount == 1 ? @"app" : @"apps"];
    } else {
        summary = [NSString stringWithFormat:@"Updates will be allowed again for %lu %@.",
            (unsigned long)unblockCount, unblockCount == 1 ? @"app" : @"apps"];
    }

    UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"Apply Changes?"
                                                                      message:summary
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [warning addAction:[UIAlertAction actionWithTitle:@"Not Now" style:UIAlertActionStyleCancel handler:nil]];
    [warning addAction:[UIAlertAction actionWithTitle:@"Apply Changes"
                                                style:UIAlertActionStyleDefault
                                              handler:^(__unused UIAlertAction *action) {
        [self applyPendingChanges];
    }]];
    [self presentViewController:warning animated:YES completion:nil];
}

- (void)applyPendingChanges
{
    NSDictionary<NSString *, NSNumber *> *changes = self.pendingStates.copy;
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:@"commit"];
    for (NSString *containerPath in changes) {
        [arguments addObject:changes[containerPath].boolValue ? @"block" : @"unblock"];
        [arguments addObject:containerPath];
    }

    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Updating App Store Status"
                                                                       message:@"Refreshing app information. Keep the device unlocked. It will respring when complete.\n\n"
                                                                preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [progress.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:progress.view.centerXAnchor],
        [spinner.bottomAnchor constraintEqualToAnchor:progress.view.bottomAnchor constant:-18.0]
    ]];
    [self presentViewController:progress animated:YES completion:nil];

    self.commitButton.enabled = NO;
    self.layoutButton.enabled = NO;
    // Keep the screen on to prevent the device from automatically locking and interrupting the Settings app during the process,
    // and ensure that the process can continue for a short while even if the app happens to move to the background.
    UIApplication *application = UIApplication.sharedApplication;
    BOOL previousIdleTimerDisabled = application.idleTimerDisabled;
    application.idleTimerDisabled = YES;
    __block UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
    void (^endKeepAwake)(void) = ^{
        application.idleTimerDisabled = previousIdleTimerDisabled;
        if (backgroundTask != UIBackgroundTaskInvalid) {
            [application endBackgroundTask:backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        }
    };
    backgroundTask = [application beginBackgroundTaskWithName:@"BlockAppUpdatesCommit"
                                            expirationHandler:^{ endKeepAwake(); }];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *errorMessage = nil;
        BOOL succeeded = [self runHelperArguments:arguments errorMessage:&errorMessage];
        dispatch_async(dispatch_get_main_queue(), ^{
            endKeepAwake();
            [progress dismissViewControllerAnimated:YES completion:^{
                [self updateLayoutButton];
                if (succeeded) {
                    [self.pendingStates removeAllObjects];
                    [self reloadApplications];
                    if (!errorMessage.length) {
                        [self restoreSavedLayoutAndRespring];
                    } else {
                        [self showMessageWithTitle:@"Changes Applied"
                            message:[errorMessage stringByAppendingString:@" Your backup is available under Restore Icon Layout."]];
                    }
                } else {
                    [self updateCommitButton];
                    [self showMessageWithTitle:@"Block App Updates"
                                      message:errorMessage ?: @"The privileged operation failed."];
                }
            }];
        });
    });
}

- (BOOL)runHelperArguments:(NSArray<NSString *> *)helperArguments
              errorMessage:(NSString **)errorMessage
{
    NSBundle *preferenceBundle = [NSBundle bundleForClass:self.class];
    NSString *helperPath = [preferenceBundle pathForResource:@"bauhelper" ofType:nil];
    if (!helperPath) {
        if (errorMessage) *errorMessage = @"The privileged helper is missing. Reinstall the package.";
        return NO;
    }

    int errorPipe[2];
    if (pipe(errorPipe) != 0) {
        if (errorMessage) *errorMessage = @"Could not create the helper communication channel.";
        return NO;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, errorPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, errorPipe[0]);

    char **arguments = calloc(helperArguments.count + 2, sizeof(char *));
    arguments[0] = (char *)helperPath.fileSystemRepresentation;
    for (NSUInteger index = 0; index < helperArguments.count; index++) {
        arguments[index + 1] = (char *)helperArguments[index].UTF8String;
    }

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, arguments[0], &actions, NULL, arguments, environ);
    free(arguments);
    posix_spawn_file_actions_destroy(&actions);
    close(errorPipe[1]);

    if (spawnResult != 0) {
        close(errorPipe[0]);
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not start the privileged helper (%d).", spawnResult];
        return NO;
    }

    NSMutableData *errorData = [NSMutableData data];
    uint8_t buffer[512];
    ssize_t bytesRead = 0;
    while ((bytesRead = read(errorPipe[0], buffer, sizeof(buffer))) > 0) {
        [errorData appendBytes:buffer length:(NSUInteger)bytesRead];
    }
    close(errorPipe[0]);

    int status = 0;
    pid_t waited;
    do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        if (errorMessage && errorData.length) {
            *errorMessage = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        return YES;
    }

    NSString *helperError = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (errorMessage) {
        *errorMessage = helperError.length > 0
            ? helperError
            : [NSString stringWithFormat:@"The privileged helper failed (status %d).", status];
    }
    return NO;
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
