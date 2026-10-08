pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQml.Models
import qs.Common
import "mapGeometry.js" as Geometry

Item {
    id: root
    objectName: "mapGeometry"
    width: 1000
    height: 500
    implicitWidth: 1000
    implicitHeight: 500
    property color mapSurfaceColor: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    property string selectedCode: ""
    property string selectedRegion: ""
    property string hoveredRegion: ""
    property bool showStates: false
    // Both tiers keep fixed paths. Only visibility changes at the zoom threshold.
    property bool detailed: true
    property var populatedStates: []
    readonly property bool ready: allVisibleShapesReady()
    readonly property int rendererType: detailed ? countries.rendererType : overviewCountries.rendererType
    readonly property string selectedCountryPath: Geometry.countryPath(selectedCode, true)
    readonly property string selectedCountryOverviewPath: Geometry.countryPath(selectedCode, false)
    readonly property string selectedStatePath: selectedCode === "US" ? Geometry.statePath(selectedRegion) : ""
    readonly property string hoveredStatePath: hoveredRegion !== selectedRegion || selectedCode !== "US" ? Geometry.statePath(hoveredRegion) : ""

    // Selection and state overlays may prepare separately from the country base.
    function allVisibleShapesReady() {
        for (const shape of children) if (typeof shape.status === "number" && shape.visible && shape.status !== Shape.Ready) return false;
        return true;
    }

    Shape {
        objectName: "mapGridShape"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillColor: "transparent"
            strokeColor: Theme.withAlpha(Theme.surfaceVariantText, 0.06)
            strokeWidth: 1
            cosmeticStroke: true
            PathSvg { path: Geometry.gridPath() }
        }
    }
    Shape {
        id: overviewCountries
        objectName: "worldOverviewShape"
        anchors.fill: parent
        visible: !root.detailed || countries.status !== Shape.Ready
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
    }
    // Each country is a separate path under one Shape. A single world fill
    // makes CurveRenderer classify every ring against all world vertices.
    Instantiator {
        model: Geometry.countriesPathRecords(false)
        delegate: ShapePath {
            id: overviewCountryPath
            objectName: "overviewCountryPath:" + modelData.code + ":" + modelData.id
            required property var modelData
            fillRule: ShapePath.OddEvenFill
            pathHints: ShapePath.PathLinear
            fillColor: Theme.withAlpha(Theme.surfaceVariantText, 0.16)
            strokeColor: Theme.withAlpha(Theme.surfaceVariantText, 0.3)
            strokeWidth: 0.6
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: overviewCountryPath.modelData.path }
        }
        onObjectAdded: (index, object) => overviewCountries.data.push(object)
    }
    Shape {
        id: countries
        objectName: "worldCountryShape"
        anchors.fill: parent
        visible: root.detailed
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
    }
    Instantiator {
        model: Geometry.countriesPathRecords(true)
        delegate: ShapePath {
            id: detailCountryPath
            objectName: "detailCountryPath:" + modelData.code + ":" + modelData.id
            required property var modelData
            fillRule: ShapePath.OddEvenFill
            pathHints: ShapePath.PathLinear
            fillColor: Theme.withAlpha(Theme.surfaceVariantText, 0.16)
            strokeColor: Theme.withAlpha(Theme.surfaceVariantText, 0.3)
            strokeWidth: 0.6
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: detailCountryPath.modelData.path }
        }
        onObjectAdded: (index, object) => countries.data.push(object)
    }
    Shape {
        objectName: "countryOverviewSelectionShape"
        anchors.fill: parent
        visible: (!root.detailed || countries.status !== Shape.Ready) && root.selectedCountryOverviewPath.length > 0
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: root.mapSurfaceColor
            strokeColor: "transparent"
            strokeWidth: -1
            PathSvg { path: root.selectedCountryOverviewPath }
        }
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: Theme.withAlpha(Theme.primary, 0.12)
            strokeColor: Theme.withAlpha(Theme.primary, 0.65)
            strokeWidth: 1.2
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.selectedCountryOverviewPath }
        }
    }
    Shape {
        objectName: "countrySelectionShape"
        anchors.fill: parent
        visible: root.detailed && countries.status === Shape.Ready && root.selectedCountryPath.length > 0
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        // Erase the neutral fill before applying the selected tint. This avoids
        // stacking translucent colors as the selected country changes.
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: root.mapSurfaceColor
            strokeColor: "transparent"
            strokeWidth: -1
            PathSvg { path: root.selectedCountryPath }
        }
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: Theme.withAlpha(Theme.primary, 0.12)
            strokeColor: Theme.withAlpha(Theme.primary, 0.65)
            strokeWidth: 1.2
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.selectedCountryPath }
        }
    }
    Shape {
        id: states
        objectName: "usStateShape"
        anchors.fill: parent
        visible: root.showStates
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: "transparent"
            strokeColor: Theme.withAlpha(Theme.surfaceVariantText, 0.4)
            strokeWidth: 0.6
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: Geometry.populatedStatesPath(root.populatedStates) }
        }
    }
    Instantiator {
        model: Geometry.statesPathRecords()
        delegate: ShapePath {
            id: statePath
            objectName: "statePath:" + modelData.name
            required property var modelData
            fillRule: ShapePath.OddEvenFill
            pathHints: ShapePath.PathLinear
            fillColor: Theme.withAlpha(Theme.surfaceVariantText, 0.02)
            strokeColor: Theme.withAlpha(Theme.surfaceVariantText, 0.25)
            strokeWidth: 0.6
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: statePath.modelData.path }
        }
        onObjectAdded: (index, object) => states.data.push(object)
    }
    Shape {
        objectName: "hoveredStateShape"
        anchors.fill: parent
        visible: root.showStates && root.hoveredStatePath.length > 0
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: Theme.withAlpha(Theme.primary, 0.12)
            strokeColor: Theme.withAlpha(Theme.primary, 0.85)
            strokeWidth: 1.2
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.hoveredStatePath }
        }
    }
    Shape {
        objectName: "selectedStateShape"
        anchors.fill: parent
        visible: root.showStates && root.selectedStatePath.length > 0
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        ShapePath {
            pathHints: ShapePath.PathLinear
            fillRule: ShapePath.OddEvenFill
            fillColor: Theme.withAlpha(Theme.primary, 0.18)
            strokeColor: Theme.withAlpha(Theme.primary, 0.85)
            strokeWidth: 1.2
            cosmeticStroke: true
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.selectedStatePath }
        }
    }
}
