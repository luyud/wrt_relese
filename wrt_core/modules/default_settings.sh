#!/usr/bin/env bash
# 系统默认设置、主题依赖与 Wi-Fi 初始化修正。

fix_default_set() {
    # 替换默认主题依赖，并注入系统设置和目标平台通用补丁。
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    local wifi_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"
    if is_vikingyfy_owrt_build; then
        local wifi_detect_path="$BUILD_DIR/package/network/config/wifi-scripts/files/etc/hotplug.d/ieee80211/10-wifi-detect"
        local wifi_patch="$BASE_PATH/patches/vikingyfy-wifi-config-defaults.patch"

        if [[ ! -f "$wifi_detect_path" ]]; then
            echo "错误：VIKINGYFY owrt 缺少预期的 IEEE 802.11 热插拔脚本：$wifi_detect_path" >&2
            return 1
        fi

        if grep -Eq '(^|[[:space:]])/sbin/wifi config --hotplug[[:space:]]*$' "$wifi_detect_path"; then
            # 新版由 mac80211.uc 提交并通知 netifd，也可能把配置生成推迟到后台。
            if ! git -C "$BUILD_DIR" apply --reverse --check "$wifi_patch" 2>/dev/null &&
                ! git -C "$BUILD_DIR" apply "$wifi_patch"; then
                echo "错误：无法将 Wi-Fi 默认值接入 VIKINGYFY owrt 的 mac80211.uc。" >&2
                return 1
            fi
        elif ! fix_legacy_vikingyfy_wifi_hotplug "$wifi_detect_path"; then
            return 1
        fi

        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/usr/libexec/992_set-wifi-uci.sh"
        rm -f "$wifi_defaults_path"
    else
        install -Dm544 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$wifi_defaults_path"
    fi

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

fix_legacy_vikingyfy_wifi_hotplug() {
    local wifi_detect_path="$1"
    local wifi_apply_line="    /usr/libexec/992_set-wifi-uci.sh --hotplug"

    if ! awk -v apply="$wifi_apply_line" '
        /^[[:space:]]*\/sbin\/wifi config$/ { config = NR; configs++ }
        $0 == apply { hook = NR; hooks++ }
        /^[[:space:]]*ubus call network\.wireless retry$/ { retry = NR; retries++ }
        END { exit !(configs == 1 && retries == 1 && config < retry &&
            (!hooks || (hooks == 1 && config < hook && hook < retry))) }
    ' "$wifi_detect_path"; then
        echo "错误：VIKINGYFY owrt 的 IEEE 802.11 热插拔流程与预期不符：$wifi_detect_path" >&2
        return 1
    fi

    if ! grep -Fqx "$wifi_apply_line" "$wifi_detect_path"; then
        sed -i '/^[[:space:]]*\/sbin\/wifi config$/a\
    /usr/libexec/992_set-wifi-uci.sh --hotplug
' "$wifi_detect_path"
    fi
}
