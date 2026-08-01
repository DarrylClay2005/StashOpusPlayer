-- Schema-loading helpers for db.py's init_db(), ported from the original
-- Python implementation (see db.py history) as the first piece of ios-bridge
-- business logic to move to Lua, embedded via lupa. Pure string processing,
-- no DB/network/crypto involved, which keeps this a low-risk first increment.

local M = {}

-- Strips `--` line comments before statements are split on `;`, so a
-- semicolon *inside* a comment (e.g. "Never echoed back to clients; see ...")
-- can't slice a comment in half and feed the trailing fragment to the DB as
-- bogus SQL. `--` only ever introduces a comment in this DDL-only schema; it
-- never appears inside a string literal.
function M.strip_sql_comments(sql)
    -- gmatch needs a trailing "\n" to yield the final line, but appending one
    -- unconditionally would manufacture a spurious empty trailing line (and
    -- statement) when `sql` already ends with "\n" — matched here instead.
    local padded = sql:sub(-1) == "\n" and sql or (sql .. "\n")
    local out = {}
    for line in padded:gmatch("(.-)\n") do
        local idx = line:find("--", 1, true)
        out[#out + 1] = idx and line:sub(1, idx - 1) or line
    end
    return table.concat(out, "\n")
end

-- Splits `sql` on `;`, except for semicolons inside a `$$ ... $$`
-- dollar-quoted block. Postgres trigger functions (the `ios_touch_*`
-- functions/triggers at the end of schema.sql) are plpgsql bodies quoted
-- with `$$ ... $$` and are themselves full of statement-terminating
-- semicolons (`NEW.x := ...;`, `RETURN NEW;`) — a plain split on `;` chops a
-- function body into fragments and feeds Postgres invalid partial statements.
function M.split_sql_statements(sql)
    local statements = {}
    local buf = {}
    local in_dollar_quote = false
    local i = 1
    local n = #sql
    while i <= n do
        if sql:sub(i, i + 1) == "$$" then
            in_dollar_quote = not in_dollar_quote
            buf[#buf + 1] = "$$"
            i = i + 2
        else
            local ch = sql:sub(i, i)
            if ch == ";" and not in_dollar_quote then
                statements[#statements + 1] = table.concat(buf)
                buf = {}
            else
                buf[#buf + 1] = ch
            end
            i = i + 1
        end
    end
    if #buf > 0 then
        statements[#statements + 1] = table.concat(buf)
    end
    return statements
end

return M
