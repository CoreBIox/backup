-- Not using slow metatables here because we need it fast
local FLOAT_PRECISION = 24

local Reader = {}

function Reader.new(bytecode)
    local stream = buffer.fromstring(bytecode)
    local cursor = 0
    local streamLen = buffer.len(stream) -- Cache buffer length for efficiency
    --
    local self = {}

    -- Helper function to check if the cursor is within bounds
    local function checkBounds(bytesNeeded)
        if cursor + bytesNeeded > streamLen then
            error("Attempt to read past the end of the buffer", 2)
        end
    end

    -- Get the length of the stream
    function self:len()
        return streamLen
    end

    -- Read the next unsigned byte
    function self:nextByte()
        checkBounds(1)
        local result = buffer.readu8(stream, cursor)
        cursor += 1
        return result
    end

    -- Read the next signed byte
    function self:nextSignedByte()
        checkBounds(1)
        local result = buffer.readi8(stream, cursor)
        cursor += 1
        return result
    end

    -- Read the next `count` bytes as a table
    function self:nextBytes(count)
        checkBounds(count)
        local result = {}
        for i = 1, count do
            table.insert(result, self:nextByte())
        end
        return result
    end

    -- Read the next byte as a character
    function self:nextChar()
        checkBounds(1)
        local result = string.char(self:nextByte())
        return result
    end

    -- Read the next unsigned 32-bit integer
    function self:nextUInt32()
        checkBounds(4)
        local result = buffer.readu32(stream, cursor)
        cursor += 4
        return result
    end

    -- Read the next signed 32-bit integer
    function self:nextInt32()
        checkBounds(4)
        local result = buffer.readi32(stream, cursor)
        cursor += 4
        return result
    end

    -- Read the next 32-bit float
    function self:nextFloat()
        checkBounds(4)
        local result = buffer.readf32(stream, cursor)
        cursor += 4
        return tonumber(string.format(`%0.{FLOAT_PRECISION}f`, result))
    end

    -- Read a variable-length integer
    function self:nextVarInt()
        local result = 0
        for i = 0, 4 do
            checkBounds(1)
            local b = self:nextByte()
            result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), i * 7))
            if not bit32.btest(b, 0x80) then
                break
            end
        end
        return result
    end

    -- Read a string of length `len` or a variable-length string
    function self:nextString(len)
        len = len or self:nextVarInt()
        if len == 0 then
            return ""
        else
            checkBounds(len)
            local result = buffer.readstring(stream, cursor, len)
            cursor += len
            return result
        end
    end

    -- Read the next 64-bit float
    function self:nextDouble()
        checkBounds(8)
        local result = buffer.readf64(stream, cursor)
        cursor += 8
        return result
    end

    return self
end

-- Set the float precision (unchanged)
function Reader:Set(...)
    FLOAT_PRECISION = ...
end

return Reader