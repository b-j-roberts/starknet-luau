--!strict
-- Contract module: ABI-driven interface, ERC-20/ERC-721 presets
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local Contract = require(script.Contract)
local ERC20 = require(script.ERC20)
local ERC721 = require(script.ERC721)
local PresetFactory = require(script.PresetFactory)

return {
	Contract = Contract,
	ERC20 = ERC20,
	ERC721 = ERC721,
	PresetFactory = PresetFactory,
}
