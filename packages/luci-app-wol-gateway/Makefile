include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wol-gateway
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-wol-gateway
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI interface for WOL Gateway
  DEPENDS:=+luci-base +rpcd
endef

define Package/luci-app-wol-gateway/description
 LuCI administration interface for the separately packaged WOL Gateway service.
endef

# Пакет содержит готовые LuCI-файлы — компиляция не требуется.
define Build/Compile
	:
endef

define Package/luci-app-wol-gateway/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/libexec/rpcd
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/wol-gateway.js $(1)/www/luci-static/resources/view/wol-gateway.js
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-wol-gateway.json $(1)/usr/share/rpcd/acl.d/luci-app-wol-gateway.json
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-wol-gateway.json $(1)/usr/share/luci/menu.d/luci-app-wol-gateway.json
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/luci.wol-gateway $(1)/usr/libexec/rpcd/luci.wol-gateway
endef

$(eval $(call BuildPackage,luci-app-wol-gateway))
