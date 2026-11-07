include $(TOPDIR)/rules.mk

PKG_NAME:=luci-i18n-oasis-zh-cn
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DEPENDS:=luci-base/host

PO2LMO:=$(STAGING_DIR_HOSTPKG)/bin/po2lmo

include $(INCLUDE_DIR)/package.mk

define Package/luci-i18n-oasis-zh-cn
  SECTION:=utakamo
  CATEGORY:=utakamo
  SUBMENU:=Translations
  TITLE:=Simplified Chinese translation for luci-app-oasis
  DEPENDS:=+luci-app-oasis +luci-i18n-base-zh-cn @LUCI_LANG_zh_Hans
  PKGARCH:=all
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/luci-i18n-oasis-zh-cn/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(PO2LMO) $(CURDIR)/po/zh_Hans/luci-app-oasis.po $(1)/usr/lib/lua/luci/i18n/oasis.zh-cn.lmo
endef

$(eval $(call BuildPackage,luci-i18n-oasis-zh-cn))
