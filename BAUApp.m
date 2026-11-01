#import "BAUApp.h"

@implementation BAUApp

- (instancetype)initWithName:(NSString *)name
             bundleIdentifier:(NSString *)bundleIdentifier
                 containerPath:(NSString *)containerPath
                    bundlePath:(NSString *)bundlePath
                       version:(NSString *)version
                       blocked:(BOOL)blocked
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _bundleIdentifier = [bundleIdentifier copy];
        _containerPath = [containerPath copy];
        _bundlePath = [bundlePath copy];
        _version = [version copy];
        _blocked = blocked;
    }
    return self;
}

@end
