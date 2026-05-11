THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VirtualCamPro
VirtualCamPro_FILES = Tweak.x
# Ensure maximum weight and stability for V117.0
VirtualCamPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -O0
VirtualCamPro_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore CoreGraphics CoreImage Foundation
VirtualCamPro_LDFLAGS += -undefined dynamic_lookup

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
