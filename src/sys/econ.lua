local econ = {}

local DEV_BALANCE_PATH = "data.dev_balance"

local function normalizeAmount(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function loadInitialBalance()
    local ok, config = pcall(require, DEV_BALANCE_PATH)

    if not ok then
        print("Unable to load dev balance: " .. tostring(config))
        return 0
    end

    if type(config) ~= "table" then
        print("Dev balance config must return a table.")
        return 0
    end

    return normalizeAmount(config.scratch)
end

local balance = loadInitialBalance()

function econ.getBalance()
    return balance
end

function econ.setBalance(value)
    balance = normalizeAmount(value)

    return balance
end

function econ.add(value)
    balance = balance + normalizeAmount(value)

    return balance
end

function econ.canAfford(value)
    return balance >= normalizeAmount(value)
end

function econ.spend(value)
    local amount = normalizeAmount(value)

    if amount > balance then
        return false
    end

    balance = balance - amount

    return true
end

return econ
