THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VirtualCamPro
VirtualCamPro_FILES = Tweak.x
VirtualCamPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VirtualCamPro_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore CoreGraphics CoreImage Foundation
VirtualCamPro_LDFLAGS += -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
