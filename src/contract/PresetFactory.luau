--!strict
-- PresetFactory: Generates preset contract modules (ERC20, ERC721, etc.)
-- Eliminates duplicated factory/validation boilerplate across presets.
-- Each preset only needs to define its ABI and call PresetFactory.create().

local Contract = require("./Contract")

local PresetFactory = {}

--- Create a preset module from a name and ABI.
--- Returns a table with .new(address, provider, account?) and .getAbi().
function PresetFactory.create(abi: Contract.Abi): { new: (string, any, any?) -> any, getAbi: () -> Contract.Abi }
	local preset = {}

	function preset.new(address: string, provider: any, account: any?): any
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
