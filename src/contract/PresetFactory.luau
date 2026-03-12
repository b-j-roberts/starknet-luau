--!strict
-- PresetFactory: Generates preset contract modules (ERC20, ERC721, etc.)
-- Eliminates duplicated factory/validation boilerplate across presets.
-- Each preset only needs to define its ABI and call PresetFactory.create().

local Contract = require("./Contract")
local Interfaces = require("../shared/interfaces")
local HexUtils = require("../shared/HexUtils")

local PresetFactory = {}

--- Create a preset module from a name and ABI.
--- Returns a table with .new(address, provider, account?) and .getAbi().
--- shortStringMethods: optional list of view method names whose felt252 results
--- should be auto-decoded to UTF-8 strings (e.g. {"name", "symbol"}).
function PresetFactory.create(
	abi: Contract.Abi,
	shortStringMethods: { string }?
): {
	new: (string, Interfaces.ProviderInterface, Interfaces.AccountInterface?) -> any,
	getAbi: () -> Contract.Abi,
}
	local preset = {}

	function preset.new(
		address: string,
		provider: Interfaces.ProviderInterface,
		account: Interfaces.AccountInterface?
	): any
		local contract = Contract.new({
			abi = abi,
			address = address,
			provider = provider,
			account = account,
		})

		if shortStringMethods then
			for _, methodName in shortStringMethods do
				rawset(contract, methodName, function(_self: any, ...: any)
					return contract:call(methodName, { ... }):andThen(function(result: any)
						return HexUtils.feltToShortString(result)
					end)
				end)
			end
		end

		return contract
	end

	function preset.getAbi(): Contract.Abi
		return abi
	end

	return preset
end

return PresetFactory
