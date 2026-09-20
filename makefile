# BD = core build directory
# HBD = hatari build subdirectory
# ZLIB_BUILD = zlib build subdirectory
# COREFILE = base filename for core object output
# COREDIR = directory for core object output
# CORESTATIC = output file for static library output
# SO_SUFFIX = filename suffix for shared object (.dll, .so, .dylib)
# CMAKEFLAGS_EXTRA = additional flags for cmake
BD ?= build
HBD ?= build
ZLIB_BUILD ?= zlib_build
COREFILE ?= hatarib
COREDIR ?= $(BD)
CORESTATIC ?= $(COREDIR)/$(COREFILE).a
SO_SUFFIX ?= auto
CFLAGS_EXTRA ?=
CMAKEFLAGS_EXTRA ?=
FPIC_FLAG ?= -fPIC

# enables debug symbols, CPU trace logging
DEBUG ?= 0

# enables verbose cmake for diagnosing the make step, and the cmake build command lines (1 = build steps, 2 = cmake trace)
VERBOSE_CMAKE ?= 0

# if multithreaded make causes problems try setting MULTITHREAD to be nothing
MULTITHREAD ?= -j

# to disable warnings as errors try setting WERROR to be nothing
WERROR ?= -Wall -Werror

# git revision hash
SHORTHASH = "$(shell git rev-parse --short HEAD || unknown)"

# PS2 Platform Configuration
ifeq ($(platform), ps2)
    CC = mips64r5900el-ps2-elf-gcc
    CXX = mips64r5900el-ps2-elf-g++
    AR = mips64r5900el-ps2-elf-ar
    FPIC_FLAG =
    WERROR =
    CFLAGS_EXTRA += -Os -march=r5900 -mtune=r5900 -G0 -ffast-math -fomit-frame-pointer -DPS2 -DABGR1555 -fno-expensive-optimizations -fcommon
    SO_SUFFIX = .a
endif

# static libraries
ZLIB_INCLUDE ?= $(PWD)/$(ZLIB_BUILD)/include
SDL2_INCLUDE ?= $(PWD)/SDL2-include
ZLIB_LIB ?= $(PWD)/$(ZLIB_BUILD)/lib/libz.a
ZLIB_LINK ?= $(ZLIB_LIB)

CC ?= gcc
AR ?= ar
CFLAGS += \
    -O3 $(WERROR) $(FPIC_FLAG) \
    -D__LIBRETRO__ -DSHORTHASH=\"$(SHORTHASH)\" \
    -Ihatari/$(HBD) -I$(SDL2_INCLUDE) -I$(ZLIB_INCLUDE) \
    $(CFLAGS_EXTRA)

ifeq ($(platform),ps2)
LDFLAGS += \
    $(WERROR) \
    -lm -Wl,--allow-multiple-definition
else
LDFLAGS += \
    -shared $(WERROR) \
    -lm
endif

CMAKE ?= cmake
CMAKEFLAGS += \
    -DZLIB_INCLUDE_DIR=$(ZLIB_INCLUDE) \
    -DZLIB_LIBRARY=$(ZLIB_LIB) \
    -DSDL2_INCLUDE_DIRS=$(SDL2_INCLUDE) \
    -DCMAKE_DISABLE_FIND_PACKAGE_Readline=1 \
    -DCMAKE_DISABLE_FIND_PACKAGE_X11=1 \
    -DCMAKE_DISABLE_FIND_PACKAGE_PNG=1 \
    -DCMAKE_DISABLE_FIND_PACKAGE_PortMidi=1 \
    -DCMAKE_DISABLE_FIND_PACKAGE_CapsImage=1

ifeq ($(platform),ps2)
CMAKEFLAGS += \
    -DCMAKE_SYSTEM_NAME=Generic \
    -DCMAKE_C_COMPILER=$(CC) \
    -DCMAKE_CXX_COMPILER=$(CXX) \
    -DCMAKE_AR=$(AR)
endif

ifeq ($(FPIC_FLAG),-fPIC)
    CMAKEFLAGS += -DCMAKE_POSITION_INDEPENDENT_CODE=ON
endif
CMAKEFLAGS += $(CMAKEFLAGS_EXTRA)
CMAKEBUILDFLAGS += $(MULTITHREAD)

ifeq ($(DEBUG),1)
    CFLAGS += -g -DCORE_DEBUG=1
    LDFLAGS += -g
    CMAKEFLAGS += -DENABLE_TRACING=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
else
    ifneq ($(shell uname),Darwin)
        ifneq ($(platform),ps2)
            LDFLAGS += -Wl,--strip-debug
        endif
    endif
    CMAKEFLAGS += -DENABLE_TRACING=0
endif

ifneq ($(VERBOSE_CMAKE),0)
ifeq ($(VERBOSE_CMAKE),2)
    CMAKEFLAGS += --trace
endif
    CMAKEBUILDFLAGS += --verbose
endif

ifeq ($(SO_SUFFIX),auto)
ifeq ($(OS),Windows_NT)
    SO_SUFFIX := .dll
    LDFLAGS += -static-libgcc
else ifeq ($(shell uname),Darwin)
    SO_SUFFIX := .dylib
else
    SO_SUFFIX := .so
    LDFLAGS += -static-libgcc
endif
endif

CORE=$(COREDIR)/$(COREFILE)$(SO_SUFFIX)
SOURCES = \
    core/core.c \
    core/core_file.c \
    core/core_input.c \
    core/core_disk.c \
    core/core_config.c \
    core/core_osk.c \
    core/core_sdl2.c
OBJECTS = $(SOURCES:%.c=$(BD)/%.o)
HATARILIBS = \
    hatari/$(HBD)/src/libcore.a \
    hatari/$(HBD)/src/falcon/libFalcon.a \
    hatari/$(HBD)/src/cpu/libUaeCpu.a \
    hatari/$(HBD)/src/gui-sdl/libGuiSdl.a \
    hatari/$(HBD)/src/libFloppy.a \
    hatari/$(HBD)/src/debug/libDebug.a \
    $(ZLIB_LINK)
# note: libcore is linked twice to allow other hatari internal libraries to resolve references within it.
HATARILIBS2 = \
    hatari/$(HBD)/src/libcore.a

.PHONY: default core static full zlib directories hatarilib clean

default: core

core: $(CORE)

# clean and rebuild everything (including static libs)
full:
    $(MAKE) -f makefile.zlib clean
    $(MAKE) clean
    $(MAKE) -f makefile.zlib
    $(MAKE) default

zlib:
    $(MAKE) -f makefile.zlib

directories:
    mkdir -p $(BD)
    mkdir -p $(BD)/core
    mkdir -p hatari/$(HBD)

ifeq ($(platform),ps2)
# For PS2, build directly as a static library archive (.a) instead of linking a .so object
$(CORE): directories hatarilib $(OBJECTS)
	$(AR) rcs $(CORE) $(OBJECTS) $(HATARILIBS) $(HATARILIBS2)
else
$(CORE): directories hatarilib $(OBJECTS)
    $(CC) -o $(CORE) $(LDFLAGS) $(OBJECTS) $(HATARILIBS) $(HATARILIBS2)
endif

# static target produces a single library $(CORESTATIC) instead of a shared object
DUMP_HATARILIBS = $(foreach a,$(HATARILIBS),DUMP_$(a))
phony: $(DUMP_HATARILIBS) dump_directories
dump_directories:
    mkdir -p $(BD)/libs
$(DUMP_HATARILIBS): dump_directories hatarilib
    $(AR) x $(patsubst DUMP_%,%,$@) --output $(BD)/libs
$(CORESTATIC): $(DUMP_HATARILIBS) $(OBJECTS)
    $(AR) r $@ $(BD)/libs/*.* $(OBJECTS)
static: directories $(CORESTATIC)

$(BD)/core/%.o: core/%.c hatarilib
    $(CC) -o $@ $(CFLAGS) -c $<

hatarilib: directories
    (cd hatari/$(HBD) && $(CMAKE) .. $(CMAKEFLAGS) -DCMAKE_C_FLAGS="$(CFLAGS)")
    (cd hatari/$(HBD) && $(CMAKE) --build . $(CMAKEBUILDFLAGS))

clean:
    rm -f -r $(BD)
    rm -f -r hatari/$(HBD)