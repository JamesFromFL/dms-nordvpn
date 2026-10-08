pragma Singleton
import QtQuick
QtObject {
    id: root
    property bool lightMode: false
    // Mutable inputs model live DMS settings without rebuilding any control.
    property var palette: ({})
    property color surfaceContainer: palette.surfaceContainer || (lightMode ? "#eeeeee" : "#1f1f1f")
    property color surfaceContainerHigh: palette.surfaceContainerHigh || (lightMode ? "#e8e8e8" : "#2a2a2a")
    property color surfaceVariantText: palette.surfaceVariantText || (lightMode ? "#474747" : "#c6c6c6")
    property color surfaceText: palette.surfaceText || (lightMode ? "#1b1b1b" : "#e2e2e2")
    property color primary: palette.primary || (lightMode ? "#00687a" : "#55d6f4")
    property color primaryText: palette.primaryText || (lightMode ? "#ffffff" : "#003640")
    property color primaryContainer: palette.primaryContainer || (lightMode ? "#acedff" : "#004e5c")
    property color primaryContainerText: palette.primaryContainerText || (lightMode ? "#001f26" : "#acedff")
    property color onPrimaryContainer
    // Native Theme uses an explicit Binding for this on-prefixed color role.
    property var primaryContainerRole: Binding {
        target: root
        property: "onPrimaryContainer"
        value: root.palette.onPrimaryContainer || root.primaryContainerText
    }
    property color error: palette.error || (lightMode ? "#ba1a1a" : "#ffb4ab")
    property color outline: palette.outline || (lightMode ? "#707070" : "#919191")
    property color widgetIconColor: palette.widgetIconColor || primary
    property color widgetInactiveIconColor: palette.widgetInactiveIconColor || withAlpha(widgetIconColor,0.6)
    property color widgetTextColor: palette.widgetTextColor || surfaceText
    property color secondary: palette.secondary || primaryContainer
    property color tertiary: palette.tertiary || secondary
    property color success: palette.success || "#6dd58c"
    property color info: palette.info || "#83c8f9"
    property color warning: palette.warning || "#e9c46a"
    property color surfaceVariant: palette.surfaceVariant || surfaceContainerHigh
    property color cardSurface: palette.cardSurface || surfaceContainer
    property color chipSurface: palette.chipSurface || surfaceContainerHigh
    property string buttonColorMode: "primary"
    readonly property color buttonBg: buttonColorMode === "primaryContainer" ? primaryContainer
        : buttonColorMode === "secondary" ? secondary : buttonColorMode === "surfaceVariant" ? surfaceVariant : primary
    readonly property color buttonText: buttonColorMode === "primaryContainer" ? onPrimaryContainer
        : buttonColorMode === "secondary" || buttonColorMode === "surfaceVariant" ? surfaceText : primaryText
    property real foregroundAlpha: 1
    property real floatingWindowForegroundAlpha: 1
    property real layerOutlineOpacity: 0.16
    readonly property color outlineVariant: withAlpha(outline, 0.6)
    readonly property color outlineMedium: withAlpha(outline, layerOutlineOpacity)
    readonly property real layerOutlineWidth: layerOutlineOpacity > 0 ? 1 : 0
    property real cornerRadius: 12
    // Native cornerRadius aliases M. The adjustable fixture M reproduces
    // strength mode; fixedRadius separately models DMS fixed-radius mode.
    property real fixedRadius: -1
    readonly property real shapeScale: cornerRadius / 12
    readonly property real cornerRadiusXS: fixedRadius >= 0 ? fixedRadius : Math.round(4 * shapeScale)
    readonly property real cornerRadiusS: fixedRadius >= 0 ? fixedRadius : Math.round(8 * shapeScale)
    readonly property real cornerRadiusM: fixedRadius >= 0 ? fixedRadius : cornerRadius
    readonly property real cornerRadiusL: fixedRadius >= 0 ? fixedRadius : Math.round(16 * shapeScale)
    readonly property real windowRadius: cornerRadiusL
    property string fontFamily: "DejaVu Sans"
    property real fontScale: 1
    property int fontWeight: Font.Normal
    readonly property int fontWeightMedium: Math.max(Font.Thin, Math.min(Font.Black, Font.Medium + fontWeight - Font.Normal))
    readonly property int fontWeightBold: Math.max(Font.Thin, Math.min(Font.Black, Font.Bold + fontWeight - Font.Normal))
    property bool scrollbarsEnabled: true
    readonly property int scrollbarThickness: 6
    readonly property int scrollbarGap: 4
    readonly property int scrollbarHideDelay: 1000
    readonly property int buttonHeightS: 40
    readonly property int iconButtonSize: 40
    readonly property int listItemHeight: 56
    readonly property int fieldHeight: Math.round(fontSizeMedium * 3)
    property int spacingXXS: 2
    property int spacingXS: 4
    property int spacingS: 8
    property int spacingM: 12
    property int spacingL: 16
    readonly property int fontSizeSmall: Math.round(fontScale * 12)
    readonly property int fontSizeMedium: Math.round(fontScale * 14)
    readonly property int fontSizeLarge: Math.round(fontScale * 16)
    readonly property int fontSizeXLarge: Math.round(fontScale * 20)
    property int iconSize: 24
    property int iconSizeLarge: 32
    function withAlpha(c,a) { return Qt.rgba(c.r,c.g,c.b,a); }
    function isFloatingWindow(item) {
        for (let current = item; current; current = current.parent) {
            if (typeof current.isFloatingWindowSurface === "boolean") return current.isFloatingWindowSurface;
            if (current.disablePopupTransparency === true) return true;
        }
        return false;
    }
    function foregroundColor(c, floatingWindow) {
        return Qt.rgba(c.r,c.g,c.b,c.a * (floatingWindow ? floatingWindowForegroundAlpha : foregroundAlpha));
    }
    function fullRadius(width, height) {
        const half = Math.max(0, Math.min(width, height)) / 2;
        return fixedRadius >= 0 ? Math.min(half, fixedRadius) : half * Math.min(1, shapeScale);
    }
    function buttonRadius(width, height, sizeHeight, pressed, round) {
        if (!pressed && round) return fullRadius(width, height);
        return sizeHeight <= 40 ? pressed ? cornerRadiusS : cornerRadiusM
            : sizeHeight <= 56 ? pressed ? cornerRadiusM : cornerRadiusL : cornerRadiusL;
    }
    function barIconSize(barThickness, offset, maximizeIcon, iconScale) {
        const size = maximizeIcon ? iconSizeLarge : iconSize;
        return 2 * Math.round(barThickness / 48 * (size + (offset === undefined ? -6 : offset))
            * (iconScale === undefined ? 1 : iconScale) / 2);
    }
    function barTextSize(barThickness, scale, maximizeText) {
        const size = barThickness / 48 <= 0.75 ? maximizeText ? fontSizeMedium : fontSizeSmall * 0.9
            : barThickness / 48 >= 1.25 ? maximizeText ? fontSizeXLarge : fontSizeMedium
            : maximizeText ? fontSizeLarge : fontSizeSmall;
        return Math.round(size * (scale === undefined ? 1 : scale));
    }
}
