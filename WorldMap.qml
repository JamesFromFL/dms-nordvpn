pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell.Widgets as QSW
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as D
import "locationLookup.js" as Geo
import "mapLogic.js" as MapMath

Rectangle {
    id: root
    objectName: "worldMap"
    property var availableCountries: []
    property var cityCatalogs: ({})
    property var availableCities: []
    property string selectedCountry: ""
    property string selectedCity: ""
    property string selectedRegion: ""
    property string connectedCountry: ""
    property string connectedCity: ""
    property real zoom: 1
    property real centerX: 0.5
    property real centerY: 0.5
    // Compact cards need additional zoom to separate nearby cities such as Boston/Nashua.
    readonly property real maxZoom: 128
    readonly property real mapWidth: Math.max(1,Math.min(width,height*2))
    readonly property real mapHeight: mapWidth / 2
    readonly property var view: ({width:width,height:height,mapWidth:mapWidth,mapHeight:mapHeight,zoom:zoom,centerX:centerX,centerY:centerY})
    readonly property var viewport: MapMath.viewport(view)
    readonly property var countryPoints: Geo.countryMarkers(availableCountries)
    // Keep this as a string so panning within the same countries doesn't rebuild delegates.
    property string detailCountriesKey: ""
    readonly property var detailCountries: detailCountriesKey ? detailCountriesKey.split("|") : []
    readonly property var currentCityPoints: Geo.cityMarkers(selectedCountry,catalogFor(selectedCountry))
    readonly property var cityPoints: {
        let points=[];
        for (const country of detailCountries) points=points.concat(Geo.cityMarkers(country,catalogFor(country)));
        return points;
    }
    readonly property var scenePoints: {
        const detailed=cityPoints;
        const expanded=new Set(detailed.map(p => p.country));
        return countryPoints.filter(p => !expanded.has(p.country)).concat(detailed);
    }
    // The view transforms existing controls immediately. Catalog discovery, clustering,
    // and label placement run at a bounded rate and preserve unchanged delegates.
    property var markers: []
    property var markerByKey: ({})
    property var automaticLabels: []
    property var labelWidthCache: Object.create(null)
    readonly property real labelHorizontalPadding: Theme.spacingS
    readonly property real labelVerticalPadding: Theme.spacingXS
    readonly property real labelGap: Theme.spacingXXS
    readonly property real labelEdgeMargin: Theme.spacingXS
    readonly property real overlayInset: Math.max(Theme.spacingS,
        Math.min(radius,width/2,height/2)*(1-Math.SQRT1_2)+border.width)
    property var clusteredInput: null
    property real clusteredZoom: 0
    property real clusteredWidth: 0
    property real clusteredHeight: 0
    property bool rebuildingScene: false
    readonly property real worldScale: mapWidth * zoom / 1000
    readonly property bool showStates: detailCountries.some(c => Geo.country(c)?.code === "US") && zoom >= 4
    readonly property var populatedStates: Geo.regions(usCountry(),catalogFor(usCountry()))
    property string hoveredRegion: ""
    signal countrySelected(string country)
    signal citySelected(string country,string city)
    signal regionSelected(string country,string region)
    signal citiesNeeded(string country)
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    radius: Theme.cornerRadiusM
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    clip: true
    implicitHeight: 300
    Accessible.name: "VPN map. Country markers connect to the fastest server. Zoom to reveal cities."

    function usCountry() { return availableCountries.find(c => Geo.country(c)?.code === "US") || ""; }
    function catalogFor(country) { return cityCatalogs[country] || (country===selectedCountry ? availableCities : []); }
    function screenX(lon) { return MapMath.screen(MapMath.project(lon,0),view).x; }
    function screenY(lat) { return MapMath.screen(MapMath.project(0,lat),view).y; }
    function pointAt(x,y) { return MapMath.unproject(x,y,view); }
    function findDetailCountries() {
        if (zoom < 2.4) return [];
        return countryPoints.filter(p => {
            const b=p.bounds;
            const extent=Math.max((b[2]-b[0])*mapWidth*zoom,(b[3]-b[1])*mapHeight*zoom);
            if (MapMath.intersects(b,viewport) && extent>=145) return true;
            return zoom>=5 && Geo.places(p.country).some(c => MapMath.onScreen({x:screenX(c.lon),y:screenY(c.lat)},view,0));
        }).map(p => p.country);
    }
    function requestVisibleCities() {
        for (const country of detailCountries) citiesNeeded(country);
    }
    function clampCenter() {
        const ex=Math.min(0.5,width/(2*mapWidth*zoom)), ey=Math.min(0.5,height/(2*mapHeight*zoom));
        centerX=Math.max(ex,Math.min(1-ex,centerX));
        centerY=Math.max(ey,Math.min(1-ey,centerY));
    }
    function zoomAt(factor,x,y) {
        const old=zoom,next=Math.max(1,Math.min(maxZoom,old*factor));
        if (!width || !height) return;
        centerX+=(x-width/2)/mapWidth*(1/old-1/next);
        centerY+=(y-height/2)/mapHeight*(1/old-1/next);
        zoom=next;clampCenter();
    }
    function resetView() { zoom=1;centerX=0.5;centerY=0.5;clampCenter(); }
    function focusBounds(bounds,maxLevel) {
        if (!width || !height) return;
        const dx=Math.max(0.008,bounds[2]-bounds[0]),dy=Math.max(0.008,bounds[3]-bounds[1]);
        zoom=Math.max(1,Math.min(maxLevel || maxZoom,width*0.78/(dx*mapWidth),height*0.7/(dy*mapHeight)));
        centerX=(bounds[0]+bounds[2])/2;centerY=(bounds[1]+bounds[3])/2;clampCenter();
    }
    function focusPoints(points,maxLevel) {
        if (!points.length) return;
        const positions=points.map(p => MapMath.project(p.lon,p.lat));
        focusBounds([Math.min(...positions.map(p=>p.x)),Math.min(...positions.map(p=>p.y)),Math.max(...positions.map(p=>p.x)),Math.max(...positions.map(p=>p.y))],maxLevel);
    }
    function focusCountry(country) {
        const target=country || selectedCountry,meta=Geo.country(target);
        if (!meta) return;
        const anchor=MapMath.project(meta.lon,meta.lat),b=meta.bounds;
        focusBounds([Math.min(b[0],anchor.x),Math.min(b[1],anchor.y),Math.max(b[2],anchor.x),Math.max(b[3],anchor.y)],16);
    }
    function focusRegion(name) { const state=Geo.state(name);if (state) focusBounds(state.bounds,48); }
    function activateMarker(marker) {
        if (marker.kind==="cluster") {
            const before=zoom;
            focusPoints(marker.members);
            if (zoom<before*1.5) { zoom=Math.min(maxZoom,before*1.8);clampCenter(); }
        } else if (marker.kind==="country") countrySelected(marker.country);
        else citySelected(marker.country,marker.city);
    }
    function selectAt(x,y) {
        if (!showStates) return;
        const p=pointAt(x,y),state=Geo.stateAt(p.x,p.y);
        if (state) { regionSelected(usCountry(),state.name);focusRegion(state.name); }
    }
    function markerKey(marker) {
        if (marker.kind !== "cluster") return marker.kind+":"+marker.country+":"+marker.city;
        return "cluster:"+marker.members.map(p => p.kind+":"+p.country+":"+(p.city || "")).sort().join("|");
    }
    function scheduleScene() { if (sceneUpdate && !sceneUpdate.running) sceneUpdate.start(); }
    function placeLabels(displayed) {
        if (zoom < 8) return [];
        const result=[], rectangles=[];
        const hitSizes=Object.create(null);
        // Count bubbles can grow with the live font. Read their actual hit size
        // once per bounded scene update, keeping labels clear of every point.
        for (const item of mapContents.children) {
            if (item.marker?.key) hitSizes[item.marker.key]=Math.max(17,item.width/2,item.height/2);
        }
        const labelHeight=markerLabelMetrics.height+labelVerticalPadding*2;
        for (const marker of displayed) {
            if (marker.kind !== "city") continue;
            let textWidth=labelWidthCache[marker.label];
            if (textWidth === undefined) {
                textWidth=markerLabelMetrics.advanceWidth(marker.label);
                labelWidthCache[marker.label]=textWidth;
            }
            const labelWidth=Math.min(textWidth+labelHorizontalPadding*2,Math.max(0,width-labelEdgeMargin*2));
            const left=Math.max(labelEdgeMargin,Math.min(width-labelEdgeMargin-labelWidth,marker.x-labelWidth/2));
            // City hit targets stay 34 px: calculate the same below/above placement as MapMarker.
            const top=marker.y+17+labelGap+labelHeight<=height-labelEdgeMargin
                ? marker.y+17+labelGap : marker.y-17-labelHeight-labelGap;
            const rectangle=[left,top,left+labelWidth,top+labelHeight];
            if (marker.x<17 || marker.x>width-17 || marker.y<17 || marker.y>height-17
                || top<labelEdgeMargin || rectangle[3]>height-labelEdgeMargin) continue;
            if (rectangles.some(other => rectangle[0]<other[2]+labelHorizontalPadding && rectangle[2]>other[0]-labelHorizontalPadding
                && rectangle[1]<other[3]+labelVerticalPadding && rectangle[3]>other[1]-labelVerticalPadding)) continue;
            if (displayed.some(other => {
                if (other === marker) return false;
                const half=hitSizes[other.key] || 17;
                return MapMath.intersects([other.x-half,other.y-half,other.x+half,other.y+half],rectangle);
            })) continue;
            result.push(marker.country+":"+marker.city);
            rectangles.push(rectangle);
        }
        return result;
    }
    function refreshScene() {
        if (!width || !height) return;
        rebuildingScene=true;
        const key=findDetailCountries().join("|");
        if (detailCountriesKey !== key) detailCountriesKey=key;
        const input=scenePoints;
        if (input !== clusteredInput || zoom !== clusteredZoom || mapWidth !== clusteredWidth || mapHeight !== clusteredHeight) {
            const snapshot={width:width,height:height,mapWidth:mapWidth,mapHeight:mapHeight,zoom:zoom,centerX:0.5,centerY:0.5};
            const next=MapMath.cluster(input,snapshot,zoom<2.4 ? 30 : 38,zoom<2.4);
            const byKey={};
            for (const marker of next) {
                marker.worldX=0.5+(marker.x-width/2)/(mapWidth*zoom);
                marker.worldY=0.5+(marker.y-height/2)/(mapHeight*zoom);
                marker.key=markerKey(marker);byKey[marker.key]=marker;
            }
            for (let i=markerTargets.count-1;i>=0;i--) if (!byKey[markerTargets.get(i).targetKey]) markerTargets.remove(i);
            markerByKey=byKey;
            const existing=new Set();
            for (let i=0;i<markerTargets.count;i++) existing.add(markerTargets.get(i).targetKey);
            for (const marker of next) if (!existing.has(marker.key)) markerTargets.append({targetKey:marker.key});
            markers=next;clusteredInput=input;clusteredZoom=zoom;clusteredWidth=mapWidth;clusteredHeight=mapHeight;
        }
        const displayed=markers.map(m => Object.assign({},m,MapMath.screen({x:m.worldX,y:m.worldY},view)));
        automaticLabels=placeLabels(displayed);
        rebuildingScene=false;
    }
    function changedView() { hoveredRegion="";scheduleScene(); }
    onZoomChanged: changedView()
    onCenterXChanged: changedView()
    onCenterYChanged: changedView()
    onScenePointsChanged: { if (!rebuildingScene) scheduleScene(); }
    onDetailCountriesKeyChanged: queryDelay.restart()
    onSelectedCountryChanged: hoveredRegion=""
    onWidthChanged: { clampCenter();scheduleScene(); }
    onHeightChanged: { clampCenter();scheduleScene(); }
    onLabelHorizontalPaddingChanged: scheduleScene()
    onLabelVerticalPaddingChanged: scheduleScene()
    onLabelGapChanged: scheduleScene()
    onLabelEdgeMarginChanged: scheduleScene()
    Component.onCompleted: refreshScene()
    FontMetrics {
        id: markerLabelMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeight
        onFontChanged: { root.labelWidthCache=Object.create(null);root.scheduleScene(); }
    }
    ListModel { id:markerTargets }
    Timer { id:sceneUpdate;interval:60;onTriggered:root.refreshScene() }
    Timer { id:queryDelay;interval:180;onTriggered:root.requestVisibleCities() }
    Timer { interval:30000;repeat:true;running:root.visible && root.detailCountries.length>0;onTriggered:root.requestVisibleCities() }

    Loader {
        id: roundedClip
        objectName: "mapRoundedClipLoader"
        anchors.fill: parent
        // Native rounded clipping uses an offscreen texture. Keep the existing
        // rectangular clip on software and before a graphics context exists.
        active: root.GraphicsInfo.api === GraphicsInfo.OpenGL || root.GraphicsInfo.api === GraphicsInfo.Vulkan
        sourceComponent: QSW.ClippingRectangle {
            objectName: "mapRoundedClip"
            radius: root.radius
            color: "transparent"
            border.width: root.border.width
            border.color: "transparent"
            contentInsideBorder: false
            contentUnderBorder: false
        }
    }
    Item {
        id: mapContents
        objectName: "mapContents"
        parent: roundedClip.item?.contentItem ?? root
        anchors.fill: parent

        MapGeometry {
            id:land
            objectName:"mapGeometry"
            width:1000;height:500
            transformOrigin:Item.TopLeft
            scale:root.worldScale
            x:root.width/2-root.centerX*root.mapWidth*root.zoom
            y:root.height/2-root.centerY*root.mapHeight*root.zoom
            selectedCode:Geo.country(root.selectedCountry)?.code || ""
            selectedRegion:root.selectedRegion
            hoveredRegion:root.hoveredRegion
            showStates:root.showStates
            populatedStates:root.populatedStates
            detailed:root.zoom>=3
            mapSurfaceColor:root.color
        }
        MouseArea {
            id:navigation
            anchors.fill:parent
            hoverEnabled:true
            cursorShape:pressed ? Qt.ClosedHandCursor : root.showStates && root.hoveredRegion ? Qt.PointingHandCursor : Qt.OpenHandCursor
            property real downX:0
            property real downY:0
            property real startX:0
            property real startY:0
            property bool moved:false
            onPressed:mouse=>{downX=mouse.x;downY=mouse.y;startX=root.centerX;startY=root.centerY;moved=false;}
            onPositionChanged:mouse=>{
                if (pressed) {
                    if (Math.abs(mouse.x-downX)+Math.abs(mouse.y-downY)>5) moved=true;
                    if (moved) {root.centerX=startX-(mouse.x-downX)/(root.mapWidth*root.zoom);root.centerY=startY-(mouse.y-downY)/(root.mapHeight*root.zoom);root.clampCenter();}
                } else if (root.showStates) {
                    const p=root.pointAt(mouse.x,mouse.y),state=Geo.stateAt(p.x,p.y);root.hoveredRegion=state ? state.name : "";
                }
            }
            onExited:root.hoveredRegion=""
            onClicked:mouse=>{if (!moved) root.selectAt(mouse.x,mouse.y);}
            onDoubleClicked:mouse=>root.zoomAt(2,mouse.x,mouse.y)
        }
        WheelHandler {
            id:wheelZoom
            target:null
            acceptedDevices:PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel:event=>{root.zoomAt(Math.pow(1.0015,event.angleDelta.y || event.pixelDelta.y*4),point.position.x,point.position.y);event.accepted=true;}
        }
        Repeater {
            model:markerTargets
            delegate:MapMarker {
                required property string targetKey
                marker:root.markerByKey[targetKey] || ({kind:"country",count:1,label:"",tooltip:"",code:"",country:"",city:"",worldX:0.5,worldY:0.5,members:[]})
                compactOverview:root.zoom<2.4 && root.mapHeight<240
                viewportWidth:root.width
                viewportHeight:root.height
                x:root.width/2+(marker.worldX-root.centerX)*root.mapWidth*root.zoom-width/2
                y:root.height/2+(marker.worldY-root.centerY)*root.mapHeight*root.zoom-height/2
                visible:x>=0 && x+width<=root.width && y>=0 && y+height<=root.height
                selected:marker.kind==="city" ? root.selectedCountry===marker.country && root.selectedCity===marker.city : marker.kind==="country" && root.selectedCountry===marker.country && !root.selectedCity
                active:(marker.kind==="country" || marker.kind==="city" && Geo.cityKey(root.connectedCity)===Geo.cityKey(marker.city)) && Geo.countryKey(root.connectedCountry)===Geo.countryKey(marker.country)
                labelVisible:(hovered || root.automaticLabels.indexOf(marker.country+":"+marker.city)>=0) && marker.kind!=="cluster"
                z:selected || hovered ? 2 : 1
                onClicked:root.activateMarker(marker)
            }
        }
        Row {
            z:10
            anchors.right:parent.right;anchors.top:parent.top;anchors.margins:root.overlayInset;spacing:Theme.spacingXS
            D.DIconButton { iconName:"add";variant:"tonal";tooltipText:"Zoom in";Accessible.name:"Zoom in";enabled:root.zoom<root.maxZoom;onClicked:root.zoomAt(1.5,root.width/2,root.height/2) }
            D.DIconButton { iconName:"remove";variant:"tonal";tooltipText:"Zoom out";Accessible.name:"Zoom out";enabled:root.zoom>1;onClicked:root.zoomAt(1/1.5,root.width/2,root.height/2) }
            D.DIconButton { iconName:"public";variant:"tonal";tooltipText:"World view";Accessible.name:"World view";onClicked:root.resetView() }
        }
        Rectangle {
            objectName: "mapLegend"
            z:10
            anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.margins:root.overlayInset
            width:Math.max(0,Math.min(root.width-root.overlayInset*2,legend.implicitWidth+Theme.spacingS*2))
            height:legend.implicitHeight+Theme.spacingXS*2
            radius:Theme.cornerRadiusS
            color:Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
            border.width:Theme.layerOutlineWidth
            border.color:Theme.outlineMedium
            StyledText {
                id:legend
                objectName: "mapLegendText"
                anchors.centerIn:parent
                width:Math.max(0,parent.width-Theme.spacingS*2)
                wrapMode:Text.NoWrap
                elide:Text.ElideRight
                color:Theme.surfaceVariantText
                font.pixelSize:Theme.fontSizeSmall
                text:root.hoveredRegion || (root.detailCountries.length ? "Cities · Click to connect · Number bubbles zoom in" : "Countries · Click for fastest server · Scroll to reveal cities")
            }
        }
    }
}
