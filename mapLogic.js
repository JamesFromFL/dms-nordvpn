.pragma library

function project(lon,lat) { return {x:(lon+180)/360,y:(90-lat)/180}; }
function screen(point,view) {
    return {x:view.width/2+(point.x-view.centerX)*view.mapWidth*view.zoom,
            y:view.height/2+(point.y-view.centerY)*view.mapHeight*view.zoom};
}
function unproject(x,y,view) {
    return {x:view.centerX+(x-view.width/2)/(view.mapWidth*view.zoom),
            y:view.centerY+(y-view.height/2)/(view.mapHeight*view.zoom)};
}
function viewport(view) {
    const a=unproject(0,0,view), b=unproject(view.width,view.height,view);
    return [a.x,a.y,b.x,b.y];
}
function intersects(a,b) { return a[0]<=b[2] && a[2]>=b[0] && a[1]<=b[3] && a[3]>=b[1]; }
function onScreen(p,view,pad) { return p.x>=pad && p.x<=view.width-pad && p.y>=pad && p.y<=view.height-pad; }

// Singles retain their exact coordinates. Only count bubbles use aggregate centroids.
// Merge until displayed hit targets have enough room, including moved centroids.
function cluster(points,view,spacing,protectCountries) {
    const groups=points.map(p => {
        const pos=screen(project(p.lon,p.lat),view);
        return {x:pos.x,y:pos.y,members:[p],count:1,
            protected:!!(protectCountries && p.kind==="country" && p.overviewPriority)};
    });
    const radius=Math.abs(spacing), spacingSquared=spacing*spacing;
    if (radius>0) {
        // Protected overview countries never merge, so eligibility is constant.
        // Keep the original pair order and restart after each moved centroid.
        let again=true;
        while (again) {
            again=false;
            outer: for (let i=0;i<groups.length;i++) {
                const a=groups[i];
                if (a.protected) continue;
                for (let j=i+1;j<groups.length;j++) {
                    const b=groups[j];
                    if (b.protected) continue;
                    const dx=a.x-b.x;
                    if (dx<=-radius || dx>=radius) continue;
                    const dy=a.y-b.y;
                    if (dx*dx+dy*dy<spacingSquared) {
                        const n=a.count,m=b.count;
                        a.x=(a.x*n+b.x*m)/(n+m);
                        a.y=(a.y*n+b.y*m)/(n+m);
                        a.members=a.members.concat(b.members);
                        a.count=n+m;
                        groups.splice(j,1);
                        again=true;
                        break outer;
                    }
                }
            }
        }
    }
    return groups.map(g => {
        const single=g.members.length===1 ? g.members[0] : null;
        const countries=Array.from(new Set(g.members.map(p => p.country)));
        return {x:g.x,y:g.y,members:g.members,count:g.members.length,
            kind:single ? single.kind : "cluster",country:single ? single.country : "",
            city:single ? single.city || "" : "",code:single ? single.code : "",
            label:single ? single.label : countries.length===1 ? g.members.length+" cities in "+countries[0].replace(/_/g," ") : g.members.length+" locations",
            tooltip:single ? single.label+(single.kind==="country" ? " · Connect to fastest server" : " · Connect to this city") : "Zoom to choose: "+g.members.slice(0,6).map(p => p.label).join(", ")+(g.members.length>6 ? "…" : "")};
    });
}

function labels(markers,zoom,viewport) {
    if (zoom<8) return [];
    const result=[],rects=[];
    for (const m of markers.filter(m => m.kind==="city")) {
        const w=m.label.length*7+16;
        const r=[m.x-w/2,m.y+19,m.x+w/2,m.y+42];
        if (viewport && (r[0]-viewport.offsetX<4 || r[2]-viewport.offsetX>viewport.width-4
            || r[1]-viewport.offsetY<4 || r[3]-viewport.offsetY>viewport.height-4)) continue;
        if (rects.some(p => intersects(p,r))) continue;
        if (markers.some(p => p!==m && intersects([p.x-17,p.y-17,p.x+17,p.y+17],r))) continue;
        result.push(m.country+":"+m.city);rects.push(r);
    }
    return result;
}
