--!strict
-- PresetFactory: Generates preset contract modules (ERC20, ERC721, etc.)
-- Eliminates duplicated factory/validation boilerplate across presets.
-- Each preset only needs to define its ABI and call PresetFactory.create().

local Contract = require("./Contract")
local Interfaces = require("../shared/interfaces")

local PresetFactory = {}

--- Create a preset module from a name and ABI.
--- Returns a table with .new(address, provider, account?) and .getAbi().
function PresetFactory.create(abi: Contract.Abi): {
	new: (string, Interfaces.ProviderInterface, Interfaces.AccountInterface?) -> any,
	getAbi: () -> Contract.Abi,
}
	local preset = {}

	function preset.new(
		address: string,
		provider: Interfaces.ProviderInterface,
		account: Interfaces.AccountInterface?
	): any
		return Contract.new({
			abi = abi,
			address = address,
			provider = provider,
			account = account,
		})
	end

	function preset.getAbi(): Contract.Abi
		return abi
	end

	return preset
end

return PresetFactory
