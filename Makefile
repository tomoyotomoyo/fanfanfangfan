TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/application.mk

# ── App name ──
APP_NAME = DFMInjector
DFMInjector_FILES = main.m AppDelegate.m RootViewController.m sandbox_escape.m apfs_own.m

# ── kexploit ──
DFMInjector_FILES += kexploit/kexploit_opa334.m kexploit/krw.m kexploit/kutils.m kexploit/offsets.m kexploit/vnode.m

# ── utils ──
DFMInjector_FILES += utils/file.c utils/hexdump.c utils/process.c

# ── kpf ──
DFMInjector_FILES += kpf/patchfinder.m

# ── XPF ──
DFMInjector_FILES += XPF/src/xpf.c XPF/src/common.c XPF/src/decompress.c XPF/src/bad_recovery.c XPF/src/non_ppl.c XPF/src/ppl.c

# ── ChOma ──
DFMInjector_FILES += XPF/external/ChOma/src/arm64.c XPF/external/ChOma/src/Base64.c XPF/external/ChOma/src/BufferedStream.c XPF/external/ChOma/src/CodeDirectory.c XPF/external/ChOma/src/CSBlob.c XPF/external/ChOma/src/DER.c XPF/external/ChOma/src/DyldSharedCache.c XPF/external/ChOma/src/Entitlements.c XPF/external/ChOma/src/Fat.c XPF/external/ChOma/src/FileStream.c XPF/external/ChOma/src/Host.c XPF/external/ChOma/src/MachO.c XPF/external/ChOma/src/MachOLoadCommand.c XPF/external/ChOma/src/MemoryStream.c XPF/external/ChOma/src/PatchFinder.c XPF/external/ChOma/src/PatchFinder_arm64.c XPF/external/ChOma/src/Util.c

# ── Flags ──
DFMInjector_CFLAGS = -I$(PWD) -I$(PWD)/XPF/src -I$(PWD)/XPF/external/ChOma/include \
    -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable \
    -Wno-incompatible-pointer-types -Wno-incompatible-pointer-types-discards-qualifiers \
    -Wno-deprecated-declarations -Wno-nonportable-include-path -Wno-format

DFMInjector_CCFLAGS = $(DFMInjector_CFLAGS)
DFMInjector_OBJCFLAGS = $(DFMInjector_CFLAGS)
DFMInjector_OBJCCFLAGS = $(DFMInjector_CFLAGS)

DFMInjector_FRAMEWORKS = UIKit Foundation WebKit AVFoundation IOKit CoreFoundation
DFMInjector_PRIVATE_FRAMEWORKS = IOSurface
DFMInjector_LIBRARIES = z sandbox

# ── Entitlements (ldid syntax: -S<file>) ──
DFMInjector_CODESIGN_FLAGS = -S$(PWD)/DFMInjector.entitlements

# ── Bundle resources ──
DFMInjector_RESOURCE_DIRS = Resources
