local _ENV = (getgenv or getfenv)()

local Implementations = {}

-- Convert number to boolean (unchanged, already efficient)
function Implementations.toBoolean(n)
    return n ~= 0
end

-- Escape a string using Lua's built-in %q specifier for reliability
function Implementations.toEscapedString(s)
    if type(s) == "string" then
        return string.format("%q", s)
    end
    return tostring(s)
end

-- Format string as a table index, ensuring valid Lua identifiers
function Implementations.formatIndexString(s)
    if type(s) == "string" then
        -- Check for valid Lua identifier (letters/underscore followed by letters/numbers/underscore, not starting with a number)
        if s:match("^[%a_][%w_]*$") and not s:match("^%d") then
            -- List of Lua keywords to avoid as direct identifiers
            local keywords = {
                "and", "break", "do", "else", "elseif", "end", "false", "for",
                "function", "goto", "if", "in", "local", "nil", "not", "or",
                "repeat", "return", "then", "true", "until", "while"
            }
            if not table.find(keywords, s) then
                return "." .. s
            end
        end
        return "[" .. Implementations.toEscapedString(s) .. "]"
    end
    return tostring(s)
end

-- Pad left with a character, with input validation
function Implementations.padLeft(x, char, padding)
    local str = tostring(x)
    local len = #str
    if type(padding) ~= "number" or padding < 0 then
        return str -- Invalid padding, return original string
    end
    if padding > len then
        return string.rep(char, padding - len) .. str
    end
    return str
end

-- Pad right with a character, with input validation
function Implementations.padRight(x, char, padding)
    local str = tostring(x)
    local len = #str
    if type(padding) ~= "number" or padding < 0 then
        return str -- Invalid padding, return original string
    end
    if padding > len then
        return str .. string.rep(char, padding - len)
    end
    return str
end

-- Check if a string is a global in the current environment
function Implementations.isGlobal(s)
    return rawget(_ENV, s) ~= nil
end

return Implementations