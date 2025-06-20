# SPDX-License-Identifier: GPL-2.0-only

TARGET         ?= $(shell uname -r)
KERNEL_MODULES := /lib/modules/$(TARGET)
KERNEL_BUILD   := $(KERNEL_MODULES)/build
SYSTEM_MAP     := /boot/System.map-$(TARGET)
DRIVER         := amd-xgbe
DRIVER_VERSION := 0.6.1

# DKMS
DKMS_ROOT_PATH_AMD_XGBE=/usr/src/amd-xgbe-$(DRIVER_VERSION)

amd-xgbe_DEST_DIR      = $(KERNEL_MODULES)/kernel/drivers/net/ethernet/amd/xgbe

obj-m  := $(patsubst %,%.o,$(DRIVER))
obj-ko := $(patsubst %,%.ko,$(DRIVER))

amd-xgbe-objs := xgbe-main.o xgbe-drv.o xgbe-dev.o \
		 xgbe-desc.o xgbe-ethtool.o xgbe-mdio.o \
		 xgbe-ptp.o \
		 xgbe-i2c.o xgbe-phy-v1.o xgbe-phy-v2.o \
		 xgbe-platform.o

amd-xgbe-$(CONFIG_PCI) += xgbe-pci.o
amd-xgbe-$(CONFIG_AMD_XGBE_DCB) += xgbe-dcb.o
amd-xgbe-$(CONFIG_DEBUG_FS) += xgbe-debugfs.o


all: modules

modules:
	@$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) modules

install: modules_modules

modules_modules:
	$(foreach mod,$(DRIVER),/usr/bin/install -m 644 -D $(mod).ko $($(mod)_DEST_DIR)/$(mod).ko;)
	depmod -a -F $(SYSTEM_MAP) $(TARGET)

clean:
	$(MAKE) -C $(KERNEL_BUILD) M=$(CURDIR) clean

.PHONY: all modules install modules_install clean

dkms:
	@mkdir -p $(DKMS_ROOT_PATH_AMD_XGBE)
	@echo "obj-m  := $(patsubst %,%.o,$(DRIVER))" >>$(DKMS_ROOT_PATH_AMD_XGBE)/Makefile
	@echo "obj-ko := $(patsubst %,%.ko,$(DRIVER))" >>$(DKMS_ROOT_PATH_AMD_XGBE)/Makefile
	@echo "amd-xgbe-objs := xgbe-main.o xgbe-drv.o xgbe-dev.o xgbe-desc.o xgbe-ethtool.o xgbe-mdio.o xgbe-ptp.o xgbe-i2c.o xgbe-phy-v1.o xgbe-phy-v2.o xgbe-platform.o xgbe-pci.o xgbe-dcb.o xgbe-debugfs.o" >>$(DKMS_ROOT_PATH_AMD_XGBE)/Makefile
	@cp dkms.conf $(DKMS_ROOT_PATH_AMD_XGBE)
	@cp *.c *.h $(DKMS_ROOT_PATH_AMD_XGBE)
	@sed -i -e '/^PACKAGE_VERSION=/ s/=.*/=\"$(DRIVER_VERSION)\"/' $(DKMS_ROOT_PATH_AMD_XGBE)/dkms.conf

	@dkms add -m amd-xgbe -v $(DRIVER_VERSION)
	@dkms build -m amd-xgbe -v $(DRIVER_VERSION)
	@dkms install --force -m amd-xgbe -v $(DRIVER_VERSION)

dkms_clean:
	@rmmod amd-xgbe 2> /dev/null || true
	@dkms remove -m amd-xgbe -v $(DRIVER_VERSION) --all
	@rm -rf $(DKMS_ROOT_PATH_AMD_XGBE)

