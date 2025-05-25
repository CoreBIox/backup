-- https://github.com/w-a-e/Advanced-Decompiler-V3

--!optimize 2

local DEFAULT_OPTIONS = {
    EnabledRemarks = {
        ColdRemark = false,
        InlineRemark = true -- currently unused
    },
    DecompilerTimeout = 10, -- seconds
    DecompilerMode = "disasm", -- optdec/disasm
    ReaderFloatPrecision = 7, -- up to 99
    ShowDebugInformation = true,
    ShowInstructionLines = false,
    ShowOperationIndex = false,
    ShowOperationNames = false,
    ShowTrivialOperations = false,
    UseTypeInfo = true,
    ListUsedGlobals = true,
    ReturnElapsedTime = false
}

local function LoadFromUrl(x)
    local BASE_URL = "https://raw.githubusercontent.com/infyiff/backup/refs/heads/main/AdvancedDecompilerV3/%s.lua"
    local success, result = pcall(game.HttpGet, game, string.format(BASE_URL, x), true)
    if not success then warn(`({math.random()}) MODULE FAILED TO LOAD FROM URL: {result}.`) return end
    local lsSuccess, lsResult = pcall(loadstring, result)
    if not lsSuccess then warn(`({math.random()}) MODULE FAILED TO LOADSTRING: {lsResult}.`) return end
    if type(lsResult) ~= "function" then warn(`MODULE IS {tostring(lsResult)} (function expected)`) return end
    return lsResult()
end

local Implementations = LoadFromUrl("Implementations")
local Reader = LoadFromUrl("Reader")
local Strings = LoadFromUrl("Strings")
local Luau = LoadFromUrl("Luau")

local function LoadFlag(name)
    local success, result = pcall(game.GetFastFlag, game, name)
    return success and result or true
end
local LuauCompileUserdataInfo = LoadFlag("LuauCompileUserdataInfo")

local LuauOpCode = Luau.OpCode
local LuauBytecodeTag = Luau.BytecodeTag
local LuauBytecodeType = Luau.BytecodeType
local LuauCaptureType = Luau.CaptureType
local LuauBuiltinFunction = Luau.BuiltinFunction
local LuauProtoFlag = Luau.ProtoFlag

local toBoolean = Implementations.toBoolean
local toEscapedString = Implementations.toEscapedString
local formatIndexString = Implementations.formatIndexString
local padLeft = Implementations.padLeft
local padRight = Implementations.padRight
local isGlobal = Implementations.isGlobal

local function Decompile(bytecode, options)
    local bytecodeVersion, typeEncodingVersion
    Reader:Set(options.ReaderFloatPrecision)
    local reader = Reader.new(bytecode)

    local function disassemble()
        if bytecodeVersion >= 4 then
            typeEncodingVersion = reader:nextByte()
        end

        local stringTable = {}
        local function readStringTable()
            local size = reader:nextVarInt()
            for i = 1, size do stringTable[i] = reader:nextString() end
        end

        local userdataTypes = {}
        local function readUserdataTypes()
            if LuauCompileUserdataInfo then
                while true do
                    local index = reader:nextByte()
                    if index == 0 then break end
                    userdataTypes[index] = reader:nextVarInt()
                end
            end
        end

        local protoTable = {}
        local function readProtoTable()
            local size = reader:nextVarInt()
            for i = 1, size do
                local protoId = i - 1
                local proto = {
                    id = protoId,
                    instructions = {},
                    constants = {},
                    captures = {},
                    innerProtos = {},
                    instructionLineInfo = {}
                }
                protoTable[protoId] = proto

                proto.maxStackSize = reader:nextByte()
                proto.numParams = reader:nextByte()
                proto.numUpvalues = reader:nextByte()
                proto.isVarArg = toBoolean(reader:nextByte())

                if bytecodeVersion >= 4 then
                    proto.flags = reader:nextByte()
                    local allTypeInfoSize = reader:nextVarInt()
                    proto.hasTypeInfo = allTypeInfoSize > 0

                    if proto.hasTypeInfo then
                        local totalTypedParams = typeEncodingVersion > 1 and reader:nextVarInt() or allTypeInfoSize
                        local totalTypedUpvalues = typeEncodingVersion > 1 and reader:nextVarInt() or 0
                        local totalTypedLocals = typeEncodingVersion > 1 and reader:nextVarInt() or 0

                        proto.typedParams = totalTypedParams > 0 and reader:nextBytes(totalTypedParams) or {}
                        if totalTypedParams > 0 then table.remove(proto.typedParams, 1); table.remove(proto.typedParams, 1) end

                        proto.typedUpvalues = {}
                        for i = 1, totalTypedUpvalues do proto.typedUpvalues[i] = { type = reader:nextByte() } end

                        proto.typedLocals = {}
                        for i = 1, totalTypedLocals do
                            proto.typedLocals[i] = {
                                type = reader:nextByte(),
                                register = reader:nextByte(),
                                startPC = reader:nextVarInt() + 1,
                                endPC = reader:nextVarInt() + reader:nextVarInt() + 1 - 1
                            }
                        end
                    end
                end

                proto.sizeInstructions = reader:nextVarInt()
                for i = 1, proto.sizeInstructions do proto.instructions[i] = reader:nextUInt32() end

                proto.sizeConstants = reader:nextVarInt()
                for i = 1, proto.sizeConstants do
                    local constType = reader:nextByte()
                    local constValue
                    if constType == LuauBytecodeTag.LBC_CONSTANT_BOOLEAN then
                        constValue = toBoolean(reader:nextByte())
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_NUMBER then
                        constValue = reader:nextDouble()
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_STRING then
                        constValue = stringTable[reader:nextVarInt()]
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_IMPORT then
                        local id = reader:nextUInt32()
                        local indexCount = bit32.rshift(id, 30)
                        local indices = {
                            bit32.band(bit32.rshift(id, 20), 0x3FF),
                            bit32.band(bit32.rshift(id, 10), 0x3FF),
                            bit32.band(id, 0x3FF)
                        }
                        local importTag = ""
                        for j = 1, indexCount do
                            importTag = importTag .. (j > 1 and "." or "") .. tostring(proto.constants[indices[j] + 1].value)
                        end
                        constValue = importTag
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_TABLE then
                        local size = reader:nextVarInt()
                        local keys = {}
                        for j = 1, size do keys[j] = reader:nextVarInt() + 1 end
                        constValue = { size = size, keys = keys }
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_CLOSURE then
                        constValue = reader:nextVarInt() + 1
                    elseif constType == LuauBytecodeTag.LBC_CONSTANT_VECTOR then
                        local x, y, z, w = reader:nextFloat(), reader:nextFloat(), reader:nextFloat(), reader:nextFloat()
                        constValue = w == 0 and ("Vector3.new("..x..", "..y..", "..z..")") or ("vector.create("..x..", "..y..", "..z..", "..w..")")
                    end
                    proto.constants[i] = { type = constType, value = constValue }
                end

                proto.sizeInnerProtos = reader:nextVarInt()
                for i = 1, proto.sizeInnerProtos do proto.innerProtos[i] = protoTable[reader:nextVarInt()] end

                proto.lineDefined = reader:nextVarInt()
                proto.name = stringTable[reader:nextVarInt()]
                proto.hasLineInfo = toBoolean(reader:nextByte())

                if proto.hasLineInfo then
                    local lineGapLog2 = reader:nextByte()
                    local baselineSize = bit32.rshift(proto.sizeInstructions - 1, lineGapLog2) + 1
                    local smallLineInfo, absLineInfo = {}, {}
                    local lastOffset, lastLine = 0, 0

                    for i = 1, proto.sizeInstructions do
                        local byte = reader:nextSignedByte()
                        lastOffset = lastOffset + byte
                        smallLineInfo[i] = lastOffset
                    end

                    for i = 1, baselineSize do
                        lastLine = lastLine + reader:nextInt32()
                        absLineInfo[i - 1] = lastLine
                    end

                    local resultLineInfo = {}
                    for i, line in smallLineInfo do
                        local absIndex = bit32.rshift(i - 1, lineGapLog2)
                        local resultLine = line + absLineInfo[absIndex]
                        if lineGapLog2 <= 1 and (-line == absLineInfo[absIndex]) then
                            resultLine = resultLine + absLineInfo[absIndex + 1]
                        end
                        if resultLine <= 0 then resultLine = resultLine + 0x100 end
                        resultLineInfo[i] = resultLine
                    end
                    proto.lineInfoSize = lineGapLog2
                    proto.instructionLineInfo = resultLineInfo
                end

                proto.hasDebugInfo = toBoolean(reader:nextByte())
                if proto.hasDebugInfo then
                    local totalDebugLocals = reader:nextVarInt()
                    proto.debugLocals = {}
                    for i = 1, totalDebugLocals do
                        proto.debugLocals[i] = {
                            name = stringTable[reader:nextVarInt()],
                            startPC = reader:nextVarInt(),
                            endPC = reader:nextVarInt(),
                            register = reader:nextByte()
                        }
                    end

                    local totalDebugUpvalues = reader:nextVarInt()
                    proto.debugUpvalues = {}
                    for i = 1, totalDebugUpvalues do
                        proto.debugUpvalues[i] = { name = stringTable[reader:nextVarInt()] }
                    end
                end
            end
        end

        readStringTable()
        if bytecodeVersion > 5 then readUserdataTypes() end
        readProtoTable()

        if #userdataTypes > 0 then warn("please send the bytecode to me so i can add support for userdata types. thanks!") end

        return reader:nextVarInt(), protoTable
    end

    local function organize()
        local function reportProtoIssue(proto, issue)
            warn(`[{proto.name or "unnamed"}:{proto.lineDefined or -1}]: {issue}`)
        end

        local mainProtoId, protoTable = disassemble()
        protoTable[mainProtoId].main = true
        local registerActions = {}

        local function baseProto(proto)
            local protoRegisterActions = {}
            registerActions[proto.id] = { proto = proto, actions = protoRegisterActions }

            local instructions = proto.instructions
            local innerProtos = proto.innerProtos
            local constants = proto.constants
            local captures = proto.captures
            local flags = proto.flags

            local function collectCaptures(baseIndex, proto)
                for i = 1, proto.numUpvalues do
                    local capture = instructions[baseIndex + i]
                    local captureType = Luau:INSN_A(capture)
                    local sourceRegister = Luau:INSN_B(capture)
                    if captureType == LuauCaptureType.LCT_VAL or captureType == LuauCaptureType.LCT_REF then
                        captures[i - 1] = sourceRegister
                    elseif captureType == LuauCaptureType.LCT_UPVAL then
                        captures[i - 1] = captures[sourceRegister]
                    end
                end
            end

            local function writeFlags()
                local decodedFlags = {}
                if proto.main then
                    decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_MODULE))
                else
                    decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_FUNCTION))
                    decodedFlags.cold = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_COLD))
                end
                proto.flags = decodedFlags
            end

            local function writeInstructions()
                local auxSkip = false
                for index, instruction in instructions do
                    if auxSkip then auxSkip = false; continue end
                    local opCodeInfo = LuauOpCode[Luau:INSN_OP(instruction)]
                    if not opCodeInfo then reportProtoIssue(proto, `invalid instruction at index "{index}"!`) continue end

                    local opCodeName = opCodeInfo.name
                    local opCodeType = opCodeInfo.type
                    local opCodeIsAux = opCodeInfo.aux == true

                    local A, B, C, sD, D, E, aux
                    if opCodeType == "A" then A = Luau:INSN_A(instruction)
                    elseif opCodeType == "E" then E = Luau:INSN_E(instruction)
                    elseif opCodeType == "AB" then A, B = Luau:INSN_A(instruction), Luau:INSN_B(instruction)
                    elseif opCodeType == "AC" then A, C = Luau:INSN_A(instruction), Luau:INSN_C(instruction)
                    elseif opCodeType == "ABC" then A, B, C = Luau:INSN_A(instruction), Luau:INSN_B(instruction), Luau:INSN_C(instruction)
                    elseif opCodeType == "AD" then A, D = Luau:INSN_A(instruction), Luau:INSN_D(instruction)
                    elseif opCodeType == "AsD" then A, sD = Luau:INSN_A(instruction), Luau:INSN_sD(instruction)
                    elseif opCodeType == "sD" then sD = Luau:INSN_sD(instruction)
                    end

                    if opCodeIsAux then auxSkip = true; aux = instructions[index + 1]; table.insert(protoRegisterActions, { hide = true }) end

                    local function registerAction(usedRegisters, extraData, hide)
                        table.insert(protoRegisterActions, { usedRegisters = usedRegisters or {}, extraData = extraData, opCode = opCodeInfo, hide = hide })
                    end

                    if opCodeName == "NOP" or opCodeName == "BREAK" then registerAction(nil, nil, not options.ShowTrivialOperations)
                    elseif opCodeName == "LOADNIL" then registerAction({A})
                    elseif opCodeName == "LOADB" then registerAction({A}, {B, C})
                    elseif opCodeName == "LOADN" then registerAction({A}, {sD})
                    elseif opCodeName == "LOADK" then registerAction({A}, {D})
                    elseif opCodeName == "MOVE" then registerAction({A, B})
                    elseif opCodeName == "GETGLOBAL" or opCodeName == "SETGLOBAL" then registerAction({A}, {aux})
                    elseif opCodeName == "GETUPVAL" or opCodeName == "SETUPVAL" then registerAction({A}, {B})
                    elseif opCodeName == "CLOSEUPVALS" then registerAction({A}, nil, not options.ShowTrivialOperations)
                    elseif opCodeName == "GETIMPORT" then registerAction({A}, {D, aux})
                    elseif opCodeName == "GETTABLE" or opCodeName == "SETTABLE" then registerAction({A, B, C})
                    elseif opCodeName == "GETTABLEKS" or opCodeName == "SETTABLEKS" then registerAction({A, B}, {C, aux})
                    elseif opCodeName == "GETTABLEN" or opCodeName == "SETTABLEN" then registerAction({A, B}, {C})
                    elseif opCodeName == "NEWCLOSURE" then
                        registerAction({A}, {D})
                        local proto = innerProtos[D + 1]
                        collectCaptures(index, proto)
                        baseProto(proto)
                    elseif opCodeName == "DUPCLOSURE" then
                        registerAction({A}, {D})
                        local proto = protoTable[constants[D + 1].value - 1]
                        collectCaptures(index, proto)
                        baseProto(proto)
                    elseif opCodeName == "NAMECALL" then registerAction({A, B}, {C, aux}, not options.ShowTrivialOperations)
                    elseif opCodeName == "CALL" then registerAction({A}, {B, C})
                    elseif opCodeName == "RETURN" then registerAction({A}, {B})
                    elseif opCodeName == "JUMP" or opCodeName == "JUMPBACK" then registerAction({}, {sD})
                    elseif opCodeName == "JUMPIF" or opCodeName == "JUMPIFNOT" then registerAction({A}, {sD})
                    elseif opCodeName:match("^JUMPIF") then registerAction({A, aux}, {sD})
                    elseif opCodeName == "ADD" or opCodeName == "SUB" or opCodeName == "MUL" or
                           opCodeName == "DIV" or opCodeName == "MOD" or opCodeName == "POW" or
                           opCodeName == "IDIV" then registerAction({A, B, C})
                    elseif opCodeName:match("K$") then registerAction({A, B}, {C})
                    elseif opCodeName == "AND" or opCodeName == "OR" then registerAction({A, B, C})
                    elseif opCodeName == "ANDK" or opCodeName == "ORK" then registerAction({A, B}, {C})
                    elseif opCodeName == "CONCAT" then
                        local registers = {A}
                        for reg = B, C do table.insert(registers, reg) end
                        registerAction(registers)
                    elseif opCodeName == "NOT" or opCodeName == "MINUS" or opCodeName == "LENGTH" then registerAction({A, B})
                    elseif opCodeName == "NEWTABLE" then registerAction({A}, {B, aux})
                    elseif opCodeName == "DUPTABLE" then registerAction({A}, {D})
                    elseif opCodeName == "SETLIST" then
                        if C ~= 0 then
                            local registers = {A, B}
                            for i = 1, C - 2 do table.insert(registers, A + i) end
                            registerAction(registers, {aux, C})
                        else
                            registerAction({A, B}, {aux, C})
                        end
                    elseif opCodeName == "FORNPREP" then registerAction({A, A+1, A+2}, {sD})
                    elseif opCodeName == "FORNLOOP" then registerAction({A}, {sD})
                    elseif opCodeName == "FORGLOOP" then
                        local numVars = bit32.band(aux, 0xFF)
                        local registers = {}
                        for i = 1, numVars do table.insert(registers, A + i) end
                        registerAction(registers, {sD, aux})
                    elseif opCodeName == "FORGPREP_INEXT" or opCodeName == "FORGPREP_NEXT" then registerAction({A, A+1})
                    elseif opCodeName == "FORGPREP" then registerAction({A}, {sD})
                    elseif opCodeName == "GETVARARGS" then
                        local registers = B ~= 0 and {A} or {A}
                        if B ~= 0 then for reg = 0, B - 1 do table.insert(registers, A + reg) end end
                        registerAction(registers, {B})
                    elseif opCodeName == "PREPVARARGS" then registerAction({}, {A}, not options.ShowTrivialOperations)
                    elseif opCodeName == "LOADKX" then registerAction({A}, {aux})
                    elseif opCodeName == "JUMPX" then registerAction({}, {E})
                    elseif opCodeName == "COVERAGE" then registerAction({}, {E}, not options.ShowTrivialOperations)
                    elseif opCodeName:match("^JUMPXEQK") then registerAction({A}, {sD, aux})
                    elseif opCodeName == "CAPTURE" then registerAction(nil, nil, not options.ShowTrivialOperations)
                    elseif opCodeName == "SUBRK" or opCodeName == "DIVRK" then registerAction({A, C}, {B})
                    elseif opCodeName == "FASTCALL" then registerAction({}, {A, C}, not options.ShowTrivialOperations)
                    elseif opCodeName == "FASTCALL1" then registerAction({B}, {A, C}, not options.ShowTrivialOperations)
                    elseif opCodeName == "FASTCALL2" then registerAction({B, bit32.band(aux, 0xFF)}, {A, C}, not options.ShowTrivialOperations)
                    elseif opCodeName == "FASTCALL2K" then registerAction({B}, {A, C, aux}, not options.ShowTrivialOperations)
                    elseif opCodeName == "FASTCALL3" then
                        local r2, r3 = bit32.band(aux, 0xFF), bit32.rshift(aux, 8)
                        registerAction({B, r2, r3}, {A, C}, not options.ShowTrivialOperations)
                    end
                end
            end

            writeFlags()
            writeInstructions()
        end
        baseProto(protoTable[mainProtoId])
        return mainProtoId, registerActions, protoTable
    end

    local function finalize(mainProtoId, registerActions, protoTable)
        local finalResult = ""
        local totalParameters = 0
        local usedGlobals = {}
        local symbolTable = {} -- Maps registers to meaningful names

        local function isValidGlobal(key)
            return not table.find(usedGlobals, key) and not isGlobal(key)
        end

        local function processResult(result)
            local embed = options.ListUsedGlobals and #usedGlobals > 0 and string.format(Strings.USED_GLOBALS, table.concat(usedGlobals, ", ")) or ""
            return embed .. result
        end

        local function inferVariableName(register, value)
            if value == "script.Parent" then return "parent"
            elseif value:match("^%a+$") then return value:lower()
            else return "v" .. register
            end
        end

        if options.DecompilerMode == "disasm" then
            local result = ""
            local function writeActions(protoActions)
                local actions = protoActions.actions
                local proto = protoActions.proto
                local instructionLineInfo = proto.instructionLineInfo
                local innerProtos = proto.innerProtos
                local constants = proto.constants
                local captures = proto.captures
                local flags = proto.flags
                local numParams = proto.numParams

                local jumpStack = {}
                totalParameters = totalParameters + numParams

                if proto.main and flags.native then result = result .. "--!native\n" end

                for i, action in actions do
                    if action.hide then continue end
                    local usedRegisters = action.usedRegisters
                    local extraData = action.extraData
                    local opCodeInfo = action.opCode
                    local opCodeName = opCodeInfo.name

                    local function handleControlFlow()
                        while #jumpStack > 0 and jumpStack[#jumpStack].endIndex == i do
                            result = result .. "end\n"
                            table.remove(jumpStack)
                        end
                    end

                    local function writeHeader()
                        local index = options.ShowOperationIndex and "[" .. padLeft(i, "0", 3) .. "] " or ""
                        local name = options.ShowOperationNames and padRight(opCodeName, " ", 15) or ""
                        local line = options.ShowInstructionLines and ":" .. padLeft(instructionLineInfo[i], "0", 3) .. ":" or ""
                        result = result .. index .. line .. name
                    end

                    local function formatRegister(register)
                        local paramIndex = register + 1
                        if paramIndex <= numParams then
                            return "p" .. (totalParameters - numParams + paramIndex)
                        end
                        return symbolTable[register] or ("v" .. (register - numParams))
                    end

                    local function formatUpvalue(register)
                        return "u_v" .. register
                    end

                    local function formatProto(proto)
                        local name = proto.name
                        local numParams = proto.numParams
                        local isVarArg = proto.isVarArg
                        local isTyped = proto.hasTypeInfo and options.UseTypeInfo
                        local flags = proto.flags
                        local typedParams = proto.typedParams

                        local protoBody = flags.native and "@native " or ""
                        protoBody = protoBody .. (name and "local function " .. name or "function") .. "("

                        for j = 1, numParams do
                            local paramBody = "p" .. (totalParameters + j)
                            if isTyped and typedParams[j] then
                                paramBody = paramBody .. ": " .. Luau:GetBaseTypeString(typedParams[j], true)
                            end
                            protoBody = protoBody .. paramBody .. (j ~= numParams and ", " or "")
                        end

                        if isVarArg then protoBody = protoBody .. (numParams > 0 and ", ..." or "...") end
                        protoBody = protoBody .. ")\n"

                        if options.ShowDebugInformation then
                            protoBody = protoBody .. "-- proto pool id: " .. proto.id .. "\n" ..
                                "-- num upvalues: " .. proto.numUpvalues .. "\n" ..
                                "-- num inner protos: " .. proto.sizeInnerProtos .. "\n" ..
                                "-- size instructions: " .. proto.sizeInstructions .. "\n" ..
                                "-- size constants: " .. proto.sizeConstants .. "\n" ..
                                "-- lineinfo gap: " .. proto.lineInfoSize .. "\n" ..
                                "-- max stack size: " .. proto.maxStackSize .. "\n" ..
                                "-- is typed: " .. tostring(proto.hasTypeInfo) .. "\n"
                        end

                        return protoBody
                    end

                    local function formatConstantValue(k)
                        if k.type == LuauBytecodeTag.LBC_CONSTANT_VECTOR then return k.value
                        else
                            local num = tonumber(k.value)
                            return num and tonumber(string.format(`%0.{options.ReaderFloatPrecision}f`, num)) or toEscapedString(k.value)
                        end
                    end

                    local function writeProto(register, proto)
                        local protoBody = formatProto(proto)
                        if proto.name then
                            result = result .. "\n" .. protoBody
                            writeActions(registerActions[proto.id])
                            result = result .. "end\n" .. formatRegister(register) .. " = " .. proto.name
                        else
                            result = result .. formatRegister(register) .. " = " .. protoBody
                            writeActions(registerActions[proto.id])
                            result = result .. "end"
                        end
                    end

                    local function writeOperationBody()
                        if opCodeName == "LOADNIL" then
                            local reg = usedRegisters[1]
                            result = result .. formatRegister(reg) .. " = nil"
                        elseif opCodeName == "LOADB" then
                            local reg = usedRegisters[1]
                            result = result .. formatRegister(reg) .. " = " .. toEscapedString(toBoolean(extraData[1]))
                        elseif opCodeName == "LOADN" then
                            local reg = usedRegisters[1]
                            result = result .. formatRegister(reg) .. " = " .. extraData[1]
                        elseif opCodeName == "LOADK" then
                            local reg = usedRegisters[1]
                            local value = formatConstantValue(constants[extraData[1] + 1])
                            result = result .. formatRegister(reg) .. " = " .. value
                            symbolTable[reg] = inferVariableName(reg, value)
                        elseif opCodeName == "MOVE" then
                            local target, source = usedRegisters[1], usedRegisters[2]
                            result = result .. formatRegister(target) .. " = " .. formatRegister(source)
                            if symbolTable[source] then symbolTable[target] = symbolTable[source] end
                        elseif opCodeName == "GETGLOBAL" then
                            local reg = usedRegisters[1]
                            local key = tostring(constants[extraData[1] + 1].value)
                            if options.ListUsedGlobals and isValidGlobal(key) then table.insert(usedGlobals, key) end
                            result = result .. formatRegister(reg) .. " = " .. key
                            symbolTable[reg] = inferVariableName(reg, key)
                        elseif opCodeName == "SETGLOBAL" then
                            local reg = usedRegisters[1]
                            local key = tostring(constants[extraData[1] + 1].value)
                            if options.ListUsedGlobals and isValidGlobal(key) then table.insert(usedGlobals, key) end
                            result = result .. key .. " = " .. formatRegister(reg)
                        elseif opCodeName == "GETUPVAL" then
                            result = result .. formatRegister(usedRegisters[1]) .. " = " .. formatUpvalue(captures[extraData[1]])
                        elseif opCodeName == "SETUPVAL" then
                            result = result .. formatUpvalue(captures[extraData[1]]) .. " = " .. formatRegister(usedRegisters[1])
                        elseif opCodeName == "GETIMPORT" then
                            local reg = usedRegisters[1]
                            local import = tostring(constants[extraData[1] + 1].value)
                            if bit32.rshift(extraData[2], 30) == 1 and options.ListUsedGlobals and isValidGlobal(import) then
                                table.insert(usedGlobals, import)
                            end
                            result = result .. formatRegister(reg) .. " = " .. import
                            symbolTable[reg] = inferVariableName(reg, import)
                        elseif opCodeName == "GETTABLE" then
                            local target, tbl, idx = usedRegisters[1], usedRegisters[2], usedRegisters[3]
                            result = result .. formatRegister(target) .. " = " .. formatRegister(tbl) .. "[" .. formatRegister(idx) .. "]"
                        elseif opCodeName == "SETTABLE" then
                            local source, tbl, idx = usedRegisters[1], usedRegisters[2], usedRegisters[3]
                            result = result .. formatRegister(tbl) .. "[" .. formatRegister(idx) .. "] = " .. formatRegister(source)
                        elseif opCodeName == "GETTABLEKS" then
                            local target, tbl = usedRegisters[1], usedRegisters[2]
                            local key = constants[extraData[2] + 1].value
                            result = result .. formatRegister(target) .. " = " .. formatRegister(tbl) .. formatIndexString(key)
                            symbolTable[target] = inferVariableName(target, formatRegister(tbl) .. "." .. key)
                        elseif opCodeName == "SETTABLEKS" then
                            local source, tbl = usedRegisters[1], usedRegisters[2]
                            local key = constants[extraData[2] + 1].value
                            result = result .. formatRegister(tbl) .. formatIndexString(key) .. " = " .. formatRegister(source)
                        elseif opCodeName == "NEWCLOSURE" then
                            writeProto(usedRegisters[1], innerProtos[extraData[1] + 1])
                        elseif opCodeName == "DUPCLOSURE" then
                            writeProto(usedRegisters[1], protoTable[constants[extraData[1] + 1].value - 1])
                        elseif opCodeName == "CALL" then
                            local base = usedRegisters[1]
                            local numArgs, numResults = extraData[1] - 1, extraData[2] - 1
                            local namecallMethod, argOffset = "", 0
                            local prev = actions[i - 1]
                            if prev and prev.opCode.name == "NAMECALL" then
                                namecallMethod = ":" .. tostring(constants[prev.extraData[2] + 1].value)
                                numArgs = numArgs - 1
                                argOffset = 1
                            end
                            local callBody = numResults > 0 and table.concat({table.unpack({formatRegister(base + j - 1) for j = 1, numResults}, 1, numResults)}, ", ") .. " = " or
                                             numResults == -1 and "... = " or ""
                            callBody = callBody .. formatRegister(base) .. namecallMethod .. "("
                            if numArgs > 0 then
                                callBody = callBody .. table.concat({table.unpack({formatRegister(base + j + argOffset) for j = 1, numArgs}, 1, numArgs)}, ", ")
                            elseif numArgs == -1 then callBody = callBody .. "..." end
                            result = result .. callBody .. ")"
                        elseif opCodeName == "RETURN" then
                            local base, total = usedRegisters[1], extraData[1] - 2
                            local retBody = total >= 0 and " " .. table.concat({table.unpack({formatRegister(base + j) for j = 0, total}, 1, total + 1)}, ", ") or
                                            total == -2 and " " .. formatRegister(base) .. ", ..." or ""
                            result = result .. "return" .. retBody
                        elseif opCodeName == "JUMPIF" then
                            local reg, offset = usedRegisters[1], extraData[1]
                            table.insert(jumpStack, {endIndex = i + offset})
                            result = result .. "if " .. formatRegister(reg) .. " then"
                        elseif opCodeName == "JUMPIFNOT" then
                            local reg, offset = usedRegisters[1], extraData[1]
                            table.insert(jumpStack, {endIndex = i + offset})
                            result = result .. "if not " .. formatRegister(reg) .. " then"
                        elseif opCodeName == "JUMPIFEQ" then
                            local left, right, offset = usedRegisters[1], usedRegisters[2], extraData[1]
                            table.insert(jumpStack, {endIndex = i + offset})
                            result = result .. "if " .. formatRegister(left) .. " == " .. formatRegister(right) .. " then"
                        elseif opCodeName == "ADD" then
                            local target, left, right = usedRegisters[1], usedRegisters[2], usedRegisters[3]
                            result = result .. formatRegister(target) .. " = " .. formatRegister(left) .. " + " .. formatRegister(right)
                        elseif opCodeName == "SUB" then
                            local target, left, right = usedRegisters[1], usedRegisters[2], usedRegisters[3]
                            result = result .. formatRegister(target) .. " = " .. formatRegister(left) .. " - " .. formatRegister(right)
                        elseif opCodeName == "NEWTABLE" then
                            result = result .. formatRegister(usedRegisters[1]) .. " = {}"
                        end
                    end

                    writeHeader()
                    writeOperationBody()
                    result = result .. "\n"
                    handleControlFlow()
                end
            end
            writeActions(registerActions[mainProtoId])
            finalResult = processResult(result)
        else
            finalResult = processResult("-- Optimized decompiler not implemented yet")
        end

        return finalResult
    end

    local function manager(proceed, issue)
        if proceed then
            local startTime = os.clock()
            local result
            task.spawn(function() result = finalize(organize()) end)
            while not result and (os.clock() - startTime) < options.DecompilerTimeout do task.wait() end
            return result and string.format(Strings.SUCCESS, result) or Strings.TIMEOUT, result and (os.clock() - startTime)
        else
            if issue == "COMPILATION_FAILURE" then
                return string.format(Strings.COMPILATION_FAILURE, reader:nextString(reader:len() - 1))
            elseif issue == "UNSUPPORTED_LBC_VERSION" then
                return Strings.UNSUPPORTED_LBC_VERSION
            end
        end
    end

    bytecodeVersion = reader:nextByte()
    if bytecodeVersion == 0 then return manager(false, "COMPILATION_FAILURE")
    elseif bytecodeVersion >= LuauBytecodeTag.LBC_VERSION_MIN and bytecodeVersion <= LuauBytecodeTag.LBC_VERSION_MAX then
        return manager(true)
    else return manager(false, "UNSUPPORTED_LBC_VERSION") end
end

local _ENV = (getgenv or getrenv or getfenv)()
_ENV.decompile = function(script, x, ...)
    if not getscriptbytecode then error("decompile is not enabled. (getscriptbytecode is missing)", 2) return end
    if typeof(script) ~= "Instance" then error("invalid argument #1 to 'decompile' (Instance expected)", 2) return end

    local function isScriptValid()
        local class = script.ClassName
        return class == "LocalScript" or class == "ModuleScript" or (class == "Script" and script.RunContext == Enum.RunContext.Client)
    end
    if not isScriptValid() then error("invalid argument #1 to 'decompile' (Instance<LocalScript, ModuleScript> expected)", 2) return end

    local success, result = pcall(getscriptbytecode, script)
    if not success or type(result) ~= "string" then error(`decompile failed to grab script bytecode: {tostring(result)}`, 2) return end

    local options = x and type(x) == "table" and table.clone(DEFAULT_OPTIONS, x) or
                    x and type(x) == "string" and table.clone(DEFAULT_OPTIONS, {DecompilerMode = x, DecompilerTimeout = select(1, ...) or 10}) or
                    DEFAULT_OPTIONS
    if x and type(x) ~= "table" and type(x) ~= "string" then error("invalid argument #2 to 'decompile' (table/string expected)", 2) return end

    local output, elapsedTime = Decompile(result, options)
    return options.ReturnElapsedTime and {output, elapsedTime} or output
end