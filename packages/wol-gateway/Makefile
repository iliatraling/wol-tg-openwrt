include $(TOPDIR)/rules.mk

PKG_NAME:=wol-gateway
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/wol-gateway
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Telegram Wake-on-LAN Gateway
  DEPENDS:=+curl +ca-bundle +etherwake +libubox
endef

define Package/wol-gateway/description
 Telegram bot service for sending Wake-on-LAN magic packets from OpenWrt.
endef

define Package/wol-gateway/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/lib/wol-gateway $(1)/etc/init.d $(1)/etc
	$(INSTALL_BIN) ./files/usr/bin/wol-gateway $(1)/usr/bin/wol-gateway
	$(INSTALL_DATA) ./files/usr/lib/wol-gateway/config.sh $(1)/usr/lib/wol-gateway/config.sh
	$(INSTALL_DATA) ./files/usr/lib/wol-gateway/telegram.sh $(1)/usr/lib/wol-gateway/telegram.sh
	$(INSTALL_DATA) ./files/usr/lib/wol-gateway/actions.sh $(1)/usr/lib/wol-gateway/actions.sh
	$(INSTALL_BIN) ./files/etc/init.d/wol-gateway $(1)/etc/init.d/wol-gateway
	$(INSTALL_CONF) ./files/etc/wol-gateway.env.example $(1)/etc/wol-gateway.env.example
endef

$(eval $(call BuildPackage,wol-gateway))
