export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:13.0

INSTALL_TARGET_PROCESSES = Minecraft

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MinecraftHelper

MinecraftHelper_FILES = Tweak.xm MHSubstrate.mm MHLogger.mm MHFeatures.mm OverlayManager.mm
MinecraftHelper_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter
MinecraftHelper_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/tweak.mk
