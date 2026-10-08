.pragma library
.import "mapData.js" as MapData
.import "locationData.js" as Locations

// Fixed geometry lives in a 1000 × 500 coordinate system. The scene transforms
// its parent for navigation; these paths never depend on the viewport or zoom.
var worldPath = null;
var overviewWorldPath = null;
var statesPath = null;
var gridPathCache = null;
var countryPaths = new Map();
var statePaths = new Map();
var populatedPaths = new Map();

function coordinate(value, scale) {
    return Math.round(value * scale * 10000) / 10000;
}

function gridPath() {
    if (gridPathCache !== null) return gridPathCache;
    const parts = [];
    for (let longitude = 0; longitude <= 12; longitude++) {
        const x = coordinate(longitude / 12, 1000);
        parts.push("M" + x + " 0L" + x + " 500");
    }
    for (let latitude = 0; latitude <= 6; latitude++) {
        const y = coordinate(latitude / 6, 500);
        parts.push("M0 " + y + "L1000 " + y);
    }
    gridPathCache = parts.join("");
    return gridPathCache;
}

function polygonsPath(polygons, detailed) {
    const parts = [];
    for (const polygon of polygons) for (const ring of detailed === false ? polygon.overview : polygon.rings) {
        if (ring.length < 3) continue;
        const first = ring[0], last = ring[ring.length - 1];
        const count = first[0] === last[0] && first[1] === last[1] ? ring.length - 1 : ring.length;
        for (let i = 0; i < count; i++) {
            const point = ring[i];
            parts.push((i ? "L" : "M") + coordinate(point[0], 1000) + " " + coordinate(point[1], 500));
        }
        parts.push("Z");
    }
    return parts.join("");
}

function countriesPath(detailed) {
    const overview = detailed === false;
    if (overview && overviewWorldPath !== null) return overviewWorldPath;
    if (!overview && worldPath !== null) return worldPath;
    const parts = [];
    for (const country of MapData.countries) {
        if (country.code !== "AQ" && country.id !== "ATA") parts.push(polygonsPath(country.polygons, detailed));
    }
    const path = parts.join("");
    if (overview) overviewWorldPath = path;
    else worldPath = path;
    return path;
}

function countryPath(code, detailed) {
    if (!code || code === "AQ") return "";
    const key = code + (detailed === false ? ":overview" : ":detail");
    if (countryPaths.has(key)) return countryPaths.get(key);
    const parts = [];
    for (const country of MapData.countries) {
        if (country.code === code) parts.push(polygonsPath(country.polygons, detailed));
    }
    const path = parts.join("");
    countryPaths.set(key, path);
    return path;
}

function statePath(name) {
    if (!name) return "";
    if (statePaths.has(name)) return statePaths.get(name);
    const state = Locations.states.find(state => state.name === name);
    const path = state ? polygonsPath(state.polygons) : "";
    statePaths.set(name, path);
    return path;
}

function allStatesPath() {
    if (statesPath !== null) return statesPath;
    statesPath = Locations.states.map(state => statePath(state.name)).join("");
    return statesPath;
}

function populatedStatesPath(names) {
    const unique = Array.from(new Set(names || [])).sort();
    const key = unique.join("|");
    if (populatedPaths.has(key)) return populatedPaths.get(key);
    const path = unique.map(name => statePath(name)).join("");
    populatedPaths.set(key, path);
    return path;
}

// Partition filled geometry by country/state to avoid full-world fill-side
// classification during CurveRenderer's asynchronous preparation. Every record
// remains stable through navigation and is shared by ShapePath delegates.
var countryRecords = new Map();
var stateRecords = null;
function countriesPathRecords(detailed) {
    const key = detailed !== false;
    if (countryRecords.has(key)) return countryRecords.get(key);
    const records = MapData.countries
        .filter(country => country.code !== "AQ" && country.id !== "ATA")
        .map(country => ({id: country.id, code: country.code, path: polygonsPath(country.polygons, detailed)}));
    countryRecords.set(key, records);
    return records;
}
function statesPathRecords() {
    if (stateRecords === null) {
        stateRecords = Locations.states.map(state => ({name: state.name, path: statePath(state.name)}));
    }
    return stateRecords;
}
