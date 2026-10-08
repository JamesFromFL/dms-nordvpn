.pragma library
.import "locationData.js" as Data

var countryIndex = null;
var officialCityIndex = null;
var fallbackCityIndex = null;
var countriesByCode = null;
function key(value) {
    return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
}
function countryKey(value) {
    const k = key(value);
    return ({unitedstatesofamerica:"unitedstates",czechia:"czechrepublic",macedonia:"northmacedonia",republicofkorea:"southkorea",turkiye:"turkey",theisleofman:"isleofman"})[k] || k;
}
function cityKey(value) {
    const k = key(value);
    return ({stlouis:"saintlouis",stpetersburg:"saintpetersburg",washingtondc:"washington"})[k] || k;
}
function buildIndices() {
    if (countryIndex) return;
    countryIndex = {}; countriesByCode = {}; officialCityIndex = {}; fallbackCityIndex = {};
    for (const c of Data.countries) for (const name of c.aliases.concat([c.name])) {
        const k = countryKey(name); if (!countryIndex[k]) countryIndex[k] = c;
    }
    // The primary country owns its name even when a dependency shares an ISO code.
    for (const c of Data.countries.filter(c => c.official)) {
        for (const name of c.aliases.concat([c.name])) countryIndex[countryKey(name)] = c;
        countriesByCode[c.code] = c;
    }
    for (const p of Data.cities) {
        if (!officialCityIndex[p.countryCode]) officialCityIndex[p.countryCode] = {};
        officialCityIndex[p.countryCode][cityKey(p.city)] = p;
    }
    for (const p of Data.fallbackCities) {
        const c = countryIndex[countryKey(p.country)];
        if (!c) continue;
        const k = c.code + ":" + cityKey(p.city);
        if (!fallbackCityIndex[k]) fallbackCityIndex[k] = [];
        fallbackCityIndex[k].push(p);
    }
}
function country(value) { buildIndices(); return countryIndex[countryKey(value)] || null; }
function places(value) {
    const c = country(value); if (!c) return [];
    return Object.values(officialCityIndex[c.code] || {});
}
function cityMarkers(value, availableCities) {
    const c = country(value); if (!c) return [];
    const official = officialCityIndex[c.code] || {};
    return availableCities.map(city => {
        const k = cityKey(city), fallback = fallbackCityIndex[c.code + ":" + k] || [];
        const match = official[k] || (fallback.length === 1 ? fallback[0] : null);
        return match ? {country:value, code:c.code, city:city, label:city.replace(/_/g," "), region:match.region, lon:match.lon, lat:match.lat, source:match.source, kind:"city"} : null;
    }).filter(Boolean);
}
function countryMarkers(availableCountries) {
    return availableCountries.map(value => {
        const c = country(value);
        return c ? {country:value, code:c.code, label:value.replace(/_/g," "), lon:c.lon, lat:c.lat, bounds:c.bounds, overviewPriority:(c.bounds[2]-c.bounds[0])*(c.bounds[3]-c.bounds[1])>=0.004, kind:"country"} : null;
    }).filter(Boolean);
}
function regionCities(value, region, availableCities) {
    return cityMarkers(value, availableCities).filter(p => key(p.region) === key(region)).map(p => p.city);
}
function regions(value, availableCities) {
    const c = country(value); if (!c || c.code !== "US") return [];
    const names = cityMarkers(value, availableCities).map(p => key(p.region));
    return Data.states.filter(s => names.indexOf(key(s.name)) >= 0).map(s => s.name).sort();
}
function state(name) { return Data.states.find(s => s.name === name); }
function inside(point, polygon) {
    let result = false;
    for (let i=0,j=polygon.length-1;i<polygon.length;j=i++) {
        const a=polygon[i],b=polygon[j];
        if ((a[1]>point[1]) !== (b[1]>point[1]) && point[0] < (b[0]-a[0])*(point[1]-a[1])/(b[1]-a[1])+a[0]) result=!result;
    }
    return result;
}
function polygonContains(point, polygon) {
    const b=polygon.bounds;
    if (b && (point[0]<b[0] || point[0]>b[2] || point[1]<b[1] || point[1]>b[3])) return false;
    if (!inside(point,polygon.rings[0])) return false;
    for (let i=1;i<polygon.rings.length;i++) if (inside(point,polygon.rings[i])) return false;
    return true;
}
function stateAt(x,y) {
    const point=[x,y];
    for (const s of Data.states) {
        const b=s.bounds;
        if (x<b[0] || x>b[2] || y<b[1] || y>b[3]) continue;
        for (const p of s.polygons) if (polygonContains(point,p)) return s;
    }
    return undefined;
}
