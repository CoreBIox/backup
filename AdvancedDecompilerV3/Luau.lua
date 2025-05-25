-- https://github.com/luau-lang/luau/raw/master/Common/include/Luau/Bytecode.h

local CASE_MULTIPLIER = 227 -- 0xE3

local Luau = {
    -- Bytecode opcodes, grouped by category for clarity
    OpCode = {
        -- Miscellaneous
        { ["name"] = "NOP", ["type"] = "none" }, -- No operation
        { ["name"] = "BREAK", ["type"] = "none" }, -- Debugger break

        -- Load operations
        { ["name"] = "LOADNIL", ["type"] = "A" }, -- Load nil into register
        { ["name"] = "LOADB", ["type"] = "ABC" }, -- Load boolean and jump
        { ["name"] = "LOADN", ["type"] = "AsD" }, -- Load number literal
        { ["name"] = "LOADK", ["type"] = "AD" }, -- Load constant

        -- Move and copy operations
        { ["name"] = "MOVE", ["type"] = "AB" }, -- Copy value between registers

        -- Global operations
        { ["name"] = "GETGLOBAL", ["type"] = "AC", ["aux"] = true }, -- Get global value
        { ["name"] = "SETGLOBAL", ["type"] = "AC", ["aux"] = true }, -- Set global value

        -- Upvalue operations
        { ["name"] = "GETUPVAL", ["type"] = "AB" }, -- Get upvalue
        { ["name"] = "SETUPVAL", ["type"] = "AB" }, -- Set upvalue
        { ["name"] = "CLOSEUPVALS", ["type"] = "A" }, -- Close upvalues

        -- Import operations
        { ["name"] = "GETIMPORT", ["type"] = "AD", ["aux"] = true }, -- Get imported global

        -- Table operations
        { ["name"] = "GETTABLE", ["type"] = "ABC" }, -- Get table value by register key
        { ["name"] = "SETTABLE", ["type"] = "ABC" }, -- Set table value by register key
        { ["name"] = "GETTABLEKS", ["type"] = "ABC", ["aux"] = true }, -- Get table value by string key
        { ["name"] = "SETTABLEKS", ["type"] = "ABC", ["aux"] = true }, -- Set table value by string key
        { ["name"] = "GETTABLEN", ["type"] = "ABC" }, -- Get table value by integer key
        { ["name"] = "SETTABLEN", ["type"] = "ABC" }, -- Set table value by integer key
        { ["name"] = "NEWTABLE", ["type"] = "AB", ["aux"] = true }, -- Create new table
        { ["name"] = "DUPTABLE", ["type"] = "AD" }, -- Duplicate table from constant

        -- Closure operations
        { ["name"] = "NEWCLOSURE", ["type"] = "AD" }, -- Create new closure
        { ["name"] = "DUPCLOSURE", ["type"] = "AD" }, -- Duplicate closure

        -- Call operations
        { ["name"] = "NAMECALL", ["type"] = "ABC", ["aux"] = true }, -- Prepare method call
        { ["name"] = "CALL", ["type"] = "ABC" }, -- Call function
        { ["name"] = "RETURN", ["type"] = "AB" }, -- Return from function

        -- Jump operations
        { ["name"] = "JUMP", ["type"] = "sD" }, -- Unconditional jump
        { ["name"] = "JUMPBACK", ["type"] = "sD" }, -- Jump back (for loops)
        { ["name"] = "JUMPIF", ["type"] = "AsD" }, -- Jump if true
        { ["name"] = "JUMPIFNOT", ["type"] = "AsD" }, -- Jump if false
        { ["name"] = "JUMPIFEQ", ["type"] = "AsD", ["aux"] = true }, -- Jump if equal
        { ["name"] = "JUMPIFLE", ["type"] = "AsD", ["aux"] = true }, -- Jump if less or equal
        { ["name"] = "JUMPIFLT", ["type"] = "AsD", ["aux"] = true }, -- Jump if less than
        { ["name"] = "JUMPIFNOTEQ", ["type"] = "AsD", ["aux"] = true }, -- Jump if not equal
        { ["name"] = "JUMPIFNOTLE", ["type"] = "AsD", ["aux"] = true }, -- Jump if not less or equal
        { ["name"] = "JUMPIFNOTLT", ["type"] = "AsD", ["aux"] = true }, -- Jump if not less than
        { ["name"] = "JUMPX", ["type"] = "E" }, -- Extended jump

        -- Arithmetic operations
        { ["name"] = "ADD", ["type"] = "ABC" }, -- Add registers
        { ["name"] = "SUB", ["type"] = "ABC" }, -- Subtract registers
        { ["name"] = "MUL", ["type"] = "ABC" }, -- Multiply registers
        { ["name"] = "DIV", ["type"] = "ABC" }, -- Divide registers
        { ["name"] = "MOD", ["type"] = "ABC" }, -- Modulo registers
        { ["name"] = "POW", ["type"] = "ABC" }, -- Power registers
        { ["name"] = "ADDK", ["type"] = "ABC" }, -- Add with constant
        { ["name"] = "SUBK", ["type"] = "ABC" }, -- Subtract with constant
        { ["name"] = "MULK", ["type"] = "ABC" }, -- Multiply with constant
        { ["name"] = "DIVK", ["type"] = "ABC" }, -- Divide with constant
        { ["name"] = "MODK", ["type"] = "ABC" }, -- Modulo with constant
        { ["name"] = "POWK", ["type"] = "ABC" }, -- Power with constant
        { ["name"] = "IDIV", ["type"] = "ABC" }, -- Integer divide registers
        { ["name"] = "IDIVK", ["type"] = "ABC" }, -- Integer divide with constant

        -- Logical operations
        { ["name"] = "AND", ["type"] = "ABC" }, -- Logical AND
        { ["name"] = "OR", ["type"] = "ABC" }, -- Logical OR
        { ["name"] = "ANDK", ["type"] = "ABC" }, -- AND with constant
        { ["name"] = "ORK", ["type"] = "ABC" }, -- OR with constant
        { ["name"] = "NOT", ["type"] = "AB" }, -- Logical NOT

        -- Unary operations
        { ["name"] = "MINUS", ["type"] = "AB" }, -- Negate value
        { ["name"] = "LENGTH", ["type"] = "AB" }, -- Get length

        -- String operations
        { ["name"] = "CONCAT", ["type"] = "ABC" }, -- Concatenate strings

        -- Loop operations
        { ["name"] = "FORNPREP", ["type"] = "AsD" }, -- Prepare numeric for loop
        { ["name"] = "FORNLOOP", ["type"] = "AsD" }, -- Numeric for loop
        { ["name"] = "FORGLOOP", ["type"] = "AsD", ["aux"] = true }, -- Generic for loop
        { ["name"] = "FORGPREP_INEXT", ["type"] = "AB" }, -- Prepare generic for ipairs
        { ["name"] = "FORGPREP_NEXT", ["type"] = "AB" }, -- Prepare generic for pairs
        { ["name"] = "FORGPREP", ["type"] = "AsD" }, -- Prepare generic for loop

        -- Vararg operations
        { ["name"] = "GETVARARGS", ["type"] = "AB" }, -- Get varargs
        { ["name"] = "PREPVARARGS", ["type"] = "A" }, -- Prepare varargs

        -- Extended operations
        { ["name"] = "LOADKX", ["type"] = "A", ["aux"] = true }, -- Load large constant
        { ["name"] = "JUMPXEQKNIL", ["type"] = "AsD", ["aux"] = true }, -- Jump if equal to nil
        { ["name"] = "JUMPXEQKB", ["type"] = "AsD", ["aux"] = true }, -- Jump if equal to boolean
        { ["name"] = "JUMPXEQKN", ["type"] = "AsD", ["aux"] = true }, -- Jump if equal to number
        { ["name"] = "JUMPXEQKS", ["type"] = "AsD", ["aux"] = true }, -- Jump if equal to string

        -- Fastcall operations
        { ["name"] = "FASTCALL", ["type"] = "ABC" }, -- Fast call builtin
        { ["name"] = "FASTCALL1", ["type"] = "ABC" }, -- Fast call with 1 arg
        { ["name"] = "FASTCALL2", ["type"] = "ABC", ["aux"] = true }, -- Fast call with 2 args
        { ["name"] = "FASTCALL2K", ["type"] = "ABC", ["aux"] = true }, -- Fast call with 1 reg + 1 const
        { ["name"] = "FASTCALL3", ["type"] = "ABC", ["aux"] = true }, -- Fast call with 3 args

        -- Miscellaneous
        { ["name"] = "COVERAGE", ["type"] = "E" }, -- Coverage tracking
        { ["name"] = "CAPTURE", ["type"] = "AB" }, -- Capture upvalue
        { ["name"] = "SUBRK", ["type"] = "ABC" }, -- Subtract constant from register
        { ["name"] = "DIVRK", ["type"] = "ABC" } -- Divide constant by register
    },
    BytecodeTag = {
        -- Bytecode version; runtime supports [MIN, MAX]
        LBC_VERSION_MIN = 3,
        LBC_VERSION_MAX = 6,
        -- Type encoding version
        LBC_TYPE_VERSION_MIN = 1,
        LBC_TYPE_VERSION_MAX = 3,
        -- Types of constant table entries
        LBC_CONSTANT_NIL = 0,
        LBC_CONSTANT_BOOLEAN = 1,
        LBC_CONSTANT_NUMBER = 2,
        LBC_CONSTANT_STRING = 3,
        LBC_CONSTANT_IMPORT = 4,
        LBC_CONSTANT_TABLE = 5,
        LBC_CONSTANT_CLOSURE = 6,
        LBC_CONSTANT_VECTOR = 7
    },
    BytecodeType = {
        LBC_TYPE_NIL = 0,
        LBC_TYPE_BOOLEAN = 1,
        LBC_TYPE_NUMBER = 2,
        LBC_TYPE_STRING = 3,
        LBC_TYPE_TABLE = 4,
        LBC_TYPE_FUNCTION = 5,
        LBC_TYPE_THREAD = 6,
        LBC_TYPE_USERDATA = 7,
        LBC_TYPE_VECTOR = 8,
        LBC_TYPE_BUFFER = 9,
        LBC_TYPE_ANY = 15,
        LBC_TYPE_TAGGED_USERDATA_BASE = 64,
        LBC_TYPE_TAGGED_USERDATA_END = 96,
        LBC_TYPE_OPTIONAL_BIT = bit32.lshift(1, 7), -- 128
        LBC_TYPE_INVALID = 256
    },
    CaptureType = {
        LCT_VAL = 0,
        LCT_REF = 1,
        LCT_UPVAL = 2
    },
    BuiltinFunction = {
        LBF_NONE = 0,
        LBF_ASSERT = 1,
        LBF_MATH_ABS = 2,
        LBF_MATH_ACOS = 3,
        LBF_MATH_ASIN = 4,
        LBF_MATH_ATAN2 = 5,
        LBF_MATH_ATAN = 6,
        LBF_MATH_CEIL = 7,
        LBF_MATH_COSH = 8,
        LBF_MATH_COS = 9,
        LBF_MATH_DEG = 10,
        LBF_MATH_EXP = 11,
        LBF_MATH_FLOOR = 12,
        LBF_MATH_FMOD = 13,
        LBF_MATH_FREXP = 14,
        LBF_MATH_LDEXP = 15,
        LBF_MATH_LOG10 = 16,
        LBF_MATH_LOG = 17,
        LBF_MATH_MAX = 18,
        LBF_MATH_MIN = 19,
        LBF_MATH_MODF = 20,
        LBF_MATH_POW = 21,
        LBF_MATH_RAD = 22,
        LBF_MATH_SINH = 23,
        LBF_MATH_SIN = 24,
        LBF_MATH_SQRT = 25,
        LBF_MATH_TANH = 26,
        LBF_MATH_TAN = 27,
        LBF_BIT32_ARSHIFT = 28,
        LBF_BIT32_BAND = 29,
        LBF_BIT32_BNOT = 30,
        LBF_BIT32_BOR = 31,
        LBF_BIT32_BXOR = 32,
        LBF_BIT32_BTEST = 33,
        LBF_BIT32_EXTRACT = 34,
        LBF_BIT32_LROTATE = 35,
        LBF_BIT32_LSHIFT = 36,
        LBF_BIT32_REPLACE = 37,
        LBF_BIT32_RROTATE = 38,
        LBF_BIT32_RSHIFT = 39,
        LBF_TYPE = 40,
        LBF_STRING_BYTE = 41,
        LBF_STRING_CHAR = 42,
        LBF_STRING_LEN = 43,
        LBF_TYPEOF = 44,
        LBF_STRING_SUB = 45,
        LBF_MATH_CLAMP = 46,
        LBF_MATH_SIGN = 47,
        LBF_MATH_ROUND = 48,
        LBF_RAWSET = 49,
        LBF_RAWGET = 50,
        LBF_RAWEQUAL = 51,
        LBF_TABLE_INSERT = 52,
        LBF_TABLE_UNPACK = 53,
        LBF_VECTOR = 54,
        LBF_BIT32_COUNTLZ = 55,
        LBF_BIT32_COUNTRZ = 56,
        LBF_SELECT_VARARG = 57,
        LBF_RAWLEN = 58,
        LBF_BIT32_EXTRACTK = 59,
        LBF_GETMETATABLE = 60,
        LBF_SETMETATABLE = 61,
        LBF_TONUMBER = 62,
        LBF_TOSTRING = 63,
        LBF_BIT32_BYTESWAP = 64,
        LBF_BUFFER_READI8 = 65,
        LBF_BUFFER_READU8 = 66,
        LBF_BUFFER_WRITEU8 = 67,
        LBF_BUFFER_READI16 = 68,
        LBF_BUFFER_READU16 = 69,
        LBF_BUFFER_WRITEU16 = 70,
        LBF_BUFFER_READI32 = 71,
        LBF_BUFFER_READU32 = 72,
        LBF_BUFFER_WRITEU32 = 73,
        LBF_BUFFER_READF32 = 74,
        LBF_BUFFER_WRITEF32 = 75,
        LBF_BUFFER_READF64 = 76,
        LBF_BUFFER_WRITEF64 = 77,
        LBF_VECTOR_MAGNITUDE = 78,
        LBF_VECTOR_NORMALIZE = 79,
        LBF_VECTOR_CROSS = 80,
        LBF_VECTOR_DOT = 81,
        LBF_VECTOR_FLOOR = 82,
        LBF_VECTOR_CEIL = 83,
        LBF_VECTOR_ABS = 84,
        LBF_VECTOR_SIGN = 85,
        LBF_VECTOR_CLAMP = 86,
        LBF_VECTOR_MIN = 87,
        LBF_VECTOR_MAX = 88
    },
    ProtoFlag = {
        LPF_NATIVE_MODULE = bit32.lshift(1, 0),
        LPF_NATIVE_COLD = bit32.lshift(1, 1),
        LPF_NATIVE_FUNCTION = bit32.lshift(1, 2)
    }
}

-- Instruction decoding functions
function Luau:INSN_OP(insn)
    return bit32.band(insn, 0xFF)
end

function Luau:INSN_A(insn)
    return bit32.band(bit32.rshift(insn, 8), 0xFF)
end

function Luau:INSN_B(insn)
    return bit32.band(bit32.rshift(insn, 16), 0xFF)
end

function Luau:INSN_C(insn)
    return bit32.band(bit32.rshift(insn, 24), 0xFF)
end

function Luau:INSN_D(insn)
    return bit32.rshift(insn, 16)
end

function Luau:INSN_sD(insn)
    local D = Luau:INSN_D(insn)
    return D > 0x7FFF and (-(0xFFFF - D) - 1) or D
end

function Luau:INSN_E(insn)
    return bit32.rshift(insn, 8)
end

-- Type to string conversion
function Luau:GetBaseTypeString(type, checkOptional)
    local tag = bit32.band(type, bit32.bnot(Luau.BytecodeType.LBC_TYPE_OPTIONAL_BIT))
    local result

    if tag == Luau.BytecodeType.LBC_TYPE_NIL then
        result = "nil"
    elseif tag == Luau.BytecodeType.LBC_TYPE_BOOLEAN then
        result = "boolean"
    elseif tag == Luau.BytecodeType.LBC_TYPE_NUMBER then
        result = "number"
    elseif tag == Luau.BytecodeType.LBC_TYPE_STRING then
        result = "string"
    elseif tag == Luau.BytecodeType.LBC_TYPE_TABLE then
        result = "table"
    elseif tag == Luau.BytecodeType.LBC_TYPE_FUNCTION then
        result = "function"
    elseif tag == Luau.BytecodeType.LBC_TYPE_THREAD then
        result = "thread"
    elseif tag == Luau.BytecodeType.LBC_TYPE_USERDATA then
        result = "userdata"
    elseif tag == Luau.BytecodeType.LBC_TYPE_VECTOR then
        result = "Vector3"
    elseif tag == Luau.BytecodeType.LBC_TYPE_BUFFER then
        result = "buffer"
    elseif tag == Luau.BytecodeType.LBC_TYPE_ANY then
        result = "any"
    else
        error("Unhandled type in GetBaseTypeString", 2)
    end

    if checkOptional then
        result = result .. (bit32.band(type, Luau.BytecodeType.LBC_TYPE_OPTIONAL_BIT) ~= 0 and "?" or "")
    end

    return result
end

-- Builtin function ID to string
function Luau:GetBuiltinInfo(bfid)
    local bf = Luau.BuiltinFunction
    if bfid == bf.LBF_NONE then return "none"
    elseif bfid == bf.LBF_ASSERT then return "assert"
    elseif bfid == bf.LBF_TYPE then return "type"
    elseif bfid == bf.LBF_TYPEOF then return "typeof"
    elseif bfid == bf.LBF_RAWSET then return "rawset"
    elseif bfid == bf.LBF_RAWGET then return "rawget"
    elseif bfid == bf.LBF_RAWEQUAL then return "rawequal"
    elseif bfid == bf.LBF_RAWLEN then return "rawlen"
    elseif bfid == bf.LBF_TABLE_UNPACK then return "unpack"
    elseif bfid == bf.LBF_SELECT_VARARG then return "select"
    elseif bfid == bf.LBF_GETMETATABLE then return "getmetatable"
    elseif bfid == bf.LBF_SETMETATABLE then return "setmetatable"
    elseif bfid == bf.LBF_TONUMBER then return "tonumber"
    elseif bfid == bf.LBF_TOSTRING then return "tostring"
    elseif bfid == bf.LBF_MATH_ABS then return "math.abs"
    elseif bfid == bf.LBF_MATH_ACOS then return "math.acos"
    elseif bfid == bf.LBF_MATH_ASIN then return "math.asin"
    elseif bfid == bf.LBF_MATH_ATAN2 then return "math.atan2"
    elseif bfid == bf.LBF_MATH_ATAN then return "math.atan"
    elseif bfid == bf.LBF_MATH_CEIL then return "math.ceil"
    elseif bfid == bf.LBF_MATH_COSH then return "math.cosh"
    elseif bfid == bf.LBF_MATH_COS then return "math.cos"
    elseif bfid == bf.LBF_MATH_DEG then return "math.deg"
    elseif bfid == bf.LBF_MATH_EXP then return "math.exp"
    elseif bfid == bf.LBF_MATH_FLOOR then return "math.floor"
    elseif bfid == bf.LBF_MATH_FMOD then return "math.fmod"
    elseif bfid == bf.LBF_MATH_FREXP then return "math.frexp"
    elseif bfid == bf.LBF_MATH_LDEXP then return "math.ldexp"
    elseif bfid == bf.LBF_MATH_LOG10 then return "math.log10"
    elseif bfid == bf.LBF_MATH_LOG then return "math.log"
    elseif bfid == bf.LBF_MATH_MAX then return "math.max"
    elseif bfid == bf.LBF_MATH_MIN then return "math.min"
    elseif bfid == bf.LBF_MATH_MODF then return "math.modf"
    elseif bfid == bf.LBF_MATH_POW then return "math.pow"
    elseif bfid == bf.LBF_MATH_RAD then return "math.rad"
    elseif bfid == bf.LBF_MATH_SINH then return "math.sinh"
    elseif bfid == bf.LBF_MATH_SIN then return "math.sin"
    elseif bfid == bf.LBF_MATH_SQRT then return "math.sqrt"
    elseif bfid == bf.LBF_MATH_TANH then return "math.tanh"
    elseif bfid == bf.LBF_MATH_TAN then return "math.tan"
    elseif bfid == bf.LBF_MATH_CLAMP then return "math.clamp"
    elseif bfid == bf.LBF_MATH_SIGN then return "math.sign"
    elseif bfid == bf.LBF_MATH_ROUND then return "math.round"
    elseif bfid == bf.LBF_BIT32_ARSHIFT then return "bit32.arshift"
    elseif bfid == bf.LBF_BIT32_BAND then return "bit32.band"
    elseif bfid == bf.LBF_BIT32_BNOT then return "bit32.bnot"
    elseif bfid == bf.LBF_BIT32_BOR then return "bit32.bor"
    elseif bfid == bf.LBF_BIT32_BXOR then return "bit32.bxor"
    elseif bfid == bf.LBF_BIT32_BTEST then return "bit32.btest"
    elseif bfid == bf.LBF_BIT32_EXTRACT or bfid == bf.LBF_BIT32_EXTRACTK then return "bit32.extract"
    elseif bfid == bf.LBF_BIT32_LROTATE then return "bit32.lrotate"
    elseif bfid == bf.LBF_BIT32_LSHIFT then return "bit32.lshift"
    elseif bfid == bf.LBF_BIT32_REPLACE then return "bit32.replace"
    elseif bfid == bf.LBF_BIT32_RROTATE then return "bit32.rrotate"
    elseif bfid == bf.LBF_BIT32_RSHIFT then return "bit32.rshift"
    elseif bfid == bf.LBF_BIT32_COUNTLZ then return "bit32.countlz"
    elseif bfid == bf.LBF_BIT32_COUNTRZ then return "bit32.countrz"
    elseif bfid == bf.LBF_BIT32_BYTESWAP then return "bit32.byteswap"
    elseif bfid == bf.LBF_STRING_BYTE then return "string.byte"
    elseif bfid == bf.LBF_STRING_CHAR then return "string.char"
    elseif bfid == bf.LBF_STRING_LEN then return "string.len"
    elseif bfid == bf.LBF_STRING_SUB then return "string.sub"
    elseif bfid == bf.LBF_TABLE_INSERT then return "table.insert"
    elseif bfid == bf.LBF_VECTOR then return "Vector3.new"
    elseif bfid == bf.LBF_BUFFER_READI8 then return "buffer.readi8"
    elseif bfid == bf.LBF_BUFFER_READU8 then return "buffer.readu8"
    elseif bfid == bf.LBF_BUFFER_WRITEU8 then return "buffer.writeu8"
    elseif bfid == bf.LBF_BUFFER_READI16 then return "buffer.readi16"
    elseif bfid == bf.LBF_BUFFER_READU16 then return "buffer.readu16"
    elseif bfid == bf.LBF_BUFFER_WRITEU16 then return "buffer.writeu16"
    elseif bfid == bf.LBF_BUFFER_READI32 then return "buffer.readi32"
    elseif bfid == bf.LBF_BUFFER_READU32 then return "buffer.readu32"
    elseif bfid == bf.LBF_BUFFER_WRITEU32 then return "buffer.writeu32"
    elseif bfid == bf.LBF_BUFFER_READF32 then return "buffer.readf32"
    elseif bfid == bf.LBF_BUFFER_WRITEF32 then return "buffer.writef32"
    elseif bfid == bf.LBF_BUFFER_READF64 then return "buffer.readf64"
    elseif bfid == bf.LBF_BUFFER_WRITEF64 then return "buffer.writef64"
    elseif bfid == bf.LBF_VECTOR_MAGNITUDE then return "vector.magnitude"
    elseif bfid == bf.LBF_VECTOR_NORMALIZE then return "vector.normalize"
    elseif bfid == bf.LBF_VECTOR_CROSS then return "vector.cross"
    elseif bfid == bf.LBF_VECTOR_DOT then return "vector.dot"
    elseif bfid == bf.LBF_VECTOR_FLOOR then return "vector.floor"
    elseif bfid == bf.LBF_VECTOR_CEIL then return "vector.ceil"
    elseif bfid == bf.LBF_VECTOR_ABS then return "vector.abs"
    elseif bfid == bf.LBF_VECTOR_SIGN then return "vector.sign"
    elseif bfid == bf.LBF_VECTOR_CLAMP then return "vector.clamp"
    elseif bfid == bf.LBF_VECTOR_MIN then return "vector.min"
    elseif bfid == bf.LBF_VECTOR_MAX then return "vector.max"
    else return "unknown" -- Default case for unhandled builtin function IDs
    end
end

-- Finalize opcode table
local function prepare(t)
    local newOpCode = {}
    for i, v in t.OpCode do
        local case = bit32.band((i - 1) * CASE_MULTIPLIER, 0xFF)
        newOpCode[case] = v
    end
    t.OpCode = newOpCode
    return t
end

return prepare(Luau)