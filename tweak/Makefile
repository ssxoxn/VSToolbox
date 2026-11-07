TARGET := iphone:clang:16.5:15.0
ARCHS  := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := VSToolbox

VSToolbox_FILES  := VSCore.mm VSUI.mm Tweak.mm
VSToolbox_CFLAGS := -fobjc-arc \
                    -Wno-deprecated-declarations \
                    -Wno-unused-function \
                    -Wno-undeclared-selector \
                    -Wno-nullability-completeness
VSToolbox_LDFLAGS := -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/library.mk

.PHONY: dylib
dylib: all
	@mkdir -p $(THEOS_PROJECT_DIR)/dist
	@cp $(firstword $(wildcard $(THEOS_OBJ_DIR)/VSToolbox.dylib $(THEOS_OBJ_DIR)/libVSToolbox.dylib)) \
	    $(THEOS_PROJECT_DIR)/dist/VSToolbox.dylib
	@echo "==> tweak/dist/VSToolbox.dylib"
	@ls -l $(THEOS_PROJECT_DIR)/dist/VSToolbox.dylib
