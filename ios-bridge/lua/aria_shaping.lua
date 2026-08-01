-- Row-shaping helpers for aria_apis.py — the second piece of ios-bridge
-- business logic moved to Lua. Python still owns the DB I/O (async
-- pool/cursor handling stays where it belongs); Lua only transforms the
-- already-fetched rows into the shape callers expect, same "no crypto/auth,
-- pure data transform" scope as lua/sql_split.lua.

local M = {}

-- rows: sequence of {genre, count} pairs (from a COUNT(*) GROUP BY query) ->
-- flat list of genre names, in the order the query already sorted them.
function M.genre_snapshot(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row[1]
    end
    return out
end

-- rows: sequence of {name, track_count} pairs -> list of
-- {name = ..., track_count = ...} tables.
function M.playlist_context(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {name = row[1], track_count = row[2]}
    end
    return out
end

return M
