ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = BlockAppUpdates

BlockAppUpdates_FILES = BAUApp.m BAURootListController.m
BlockAppUpdates_FRAMEWORKS = UIKit CoreServices
BlockAppUpdates_PRIVATE_FRAMEWORKS = Preferences
BlockAppUpdates_INSTALL_PATH = /Library/PreferenceBundles
BlockAppUpdates_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

TOOL_NAME = bauhelper

bauhelper_FILES = BAUHelper.m
bauhelper_FRAMEWORKS = Foundation CoreServices
bauhelper_INSTALL_PATH = /Library/PreferenceBundles/BlockAppUpdates.bundle
bauhelper_CFLAGS = -fobjc-arc
bauhelper_CODESIGN_FLAGS = -SBAUHelper.entitlements

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "killall -9 Preferences 2>/dev/null || true"
