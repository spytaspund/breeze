TARGET = iphone:clang:6.0:6.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TOOL_NAME = breezed

breezed_FILES = main.m
breezed_FRAMEWORKS = Foundation CoreLocation
breezed_CFLAGS = -fPIE
breezed_LDFLAGS = -fPIE
breezed_INSTALL_PATH = /usr/bin
breezed_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/tool.mk
