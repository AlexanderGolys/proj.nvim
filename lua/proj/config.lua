-- @@@proj.config

---@class proj.SetupConfig
---@field open_weighting fun(date_rank: integer): float
 

---@type proj.SetupConfig
return {
    open_weighting = function(date_rank) return 1 / math.sqrt(date_rank) end,
}


