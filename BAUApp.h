#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BAUApp : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *containerPath;
@property (nonatomic, copy, readonly) NSString *bundlePath;
@property (nonatomic, copy, readonly, nullable) NSString *version;
@property (nonatomic, assign, readonly, getter=isBlocked) BOOL blocked;

- (instancetype)initWithName:(NSString *)name
             bundleIdentifier:(NSString *)bundleIdentifier
                 containerPath:(NSString *)containerPath
                    bundlePath:(NSString *)bundlePath
                       version:(nullable NSString *)version
                       blocked:(BOOL)blocked;

@end

NS_ASSUME_NONNULL_END
