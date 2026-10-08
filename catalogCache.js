.pragma library

var softAgeMs = 24 * 60 * 60 * 1000;
var hardAgeMs = 7 * softAgeMs;
var futureToleranceMs = 5 * 60 * 1000;
var maxCountries = 300;
var maxCitiesPerCountry = 512;
var maxTotalCities = 5000;
var maxInputBytes = 256 * 1024;
var tokenPattern = /^[A-Za-z][A-Za-z0-9_-]{0,79}$/;

function emptyPayload() {
    return { schema: 1, catalogs: Object.create(null) };
}
function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}
function owns(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
}
function number(value) {
    return typeof value === "number" && isFinite(value) && value > 0;
}
function token(value) {
    return typeof value === "string" && tokenPattern.test(value);
}
function timestamp(value, now, age) {
    return number(now) && number(value) && value <= now + futureToleranceMs && now - value <= age;
}
function fresh(value, now) {
    return timestamp(value, now, softAgeMs) && now - value < softAgeMs;
}

function inputFits(payload) {
    const text = JSON.stringify(payload);
    if (typeof text !== "string" || text.length > maxInputBytes) return false;
    // JSON length is UTF-16; count UTF-8 bytes so unknown Unicode fields cannot
    // bypass the serialized input bound. Unpaired surrogates are JSON-escaped.
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code < 0x80) bytes++;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
            && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            bytes += 4;
            i++;
        } else bytes += 3;
        if (bytes > maxInputBytes) return false;
    }
    return true;
}

function read(payload, now) {
    const result = emptyPayload();
    try {
        if (!number(now) || !object(payload) || !owns(payload, "schema") || payload.schema !== 1
            || !owns(payload, "catalogs") || !object(payload.catalogs) || !inputFits(payload)) return result;
        const countries = Object.keys(payload.catalogs);
        if (countries.length > maxCountries) return result;
        let total = 0;
        for (const country of countries) {
            const record = payload.catalogs[country];
            if (!token(country) || !object(record) || !owns(record, "cities")
                || !Array.isArray(record.cities) || record.cities.length > maxCitiesPerCountry
                || !owns(record, "checkedAt") || !timestamp(record.checkedAt, now, hardAgeMs)) continue;
            const cities = [], seen = Object.create(null);
            let valid = true;
            for (const city of record.cities) {
                if (!token(city)) { valid = false; break; }
                if (!seen[city]) { seen[city] = true; cities.push(city); }
            }
            // A malformed city invalidates the entire country, never a partial list.
            if (!valid) continue;
            total += record.cities.length;
            if (total > maxTotalCities) return emptyPayload();
            result.catalogs[country] = { cities: cities, checkedAt: record.checkedAt };
        }
    } catch (error) {
        return emptyPayload();
    }
    return result;
}

function pack(catalogs, updated, liveCountries, now) {
    try {
        if (!object(catalogs) || !object(updated) || !Array.isArray(liveCountries)
            || liveCountries.length > maxCountries) return emptyPayload();
        const countries = Object.keys(catalogs);
        if (countries.length > maxCountries) return emptyPayload();
        const live = Object.create(null), records = Object.create(null);
        for (const country of liveCountries) if (token(country)) live[country] = true;
        for (const country of countries) {
            if (!live[country] || !owns(updated, country)) continue;
            records[country] = { cities: catalogs[country], checkedAt: updated[country] };
        }
        // Reuse the same schema, token, timestamp, expiry and resource checks.
        return read({ schema: 1, catalogs: records }, now);
    } catch (error) {
        return emptyPayload();
    }
}
