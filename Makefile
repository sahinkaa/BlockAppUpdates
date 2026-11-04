DEBUG = 0
FINALPACKAGE = 1

THEOS_DEVICE_IP = 127.0.0.1 -p 2222
INSTALL_TARGET_PROCESSES = backboardd

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

BUNDLE_NAME = BlockAppUpdates
TOOL_NAME = bauhelper
TWEAK_NAME = BAULayout
BAULayout_FILES = BAULayout.m
BAULayout_CFLAGS = -fobjc-arc
BAULayout_FRAMEWORKS = Foundation

$(BUNDLE_NAME)_FILES = BAUApp.m BAURootListController.m
$(BUNDLE_NAME)_FRAMEWORKS = UIKit CoreServices
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_LDFLAGS = -F$(THEOS_PROJECT_DIR)/vendor
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
$(BUNDLE_NAME)_LIBRARIES = roothide
$(TOOL_NAME)_LIBRARIES = roothide
BAULayout_LIBRARIES = roothide
endif

$(TOOL_NAME)_FILES = BAUHelper.m
$(TOOL_NAME)_FRAMEWORKS = Foundation CoreServices
$(TOOL_NAME)_INSTALL_PATH = /Library/PreferenceBundles/$(BUNDLE_NAME).bundle
$(TOOL_NAME)_CFLAGS = -fobjc-arc
$(TOOL_NAME)_CODESIGN_FLAGS = -SBAUHelper.entitlements

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/tweak.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/$(BUNDLE_NAME).plist$(ECHO_END)

before-package::
	$(ECHO_NOTHING)find "$(THEOS_STAGING_DIR)" -type d -exec chmod 0755 {} +$(ECHO_END)
	$(ECHO_NOTHING)find "$(THEOS_STAGING_DIR)" -type f ! -path "*/DEBIAN/*" ! -name BlockAppUpdates ! -name bauhelper ! -name BAULayout.dylib -exec chmod 0644 {} +$(ECHO_END)
	$(ECHO_NOTHING)find "$(THEOS_STAGING_DIR)" -type f -name BlockAppUpdates -exec chmod 0755 {} +$(ECHO_END)
	$(ECHO_NOTHING)find "$(THEOS_STAGING_DIR)" -type f -name bauhelper -exec chmod 4755 {} +$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"$(ECHO_END)
