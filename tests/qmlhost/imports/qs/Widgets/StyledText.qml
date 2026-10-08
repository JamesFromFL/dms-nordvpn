import QtQuick
import qs.Common
Text {
    color: Theme.surfaceText
    // Native StyledText's default stays 14; scale requires explicit Theme size.
    font.pixelSize: 14
    font.family: Theme.fontFamily
    font.weight: Theme.fontWeight
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
