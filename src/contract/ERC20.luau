--!strict
-- ERC20: Pre-built contract interface for ERC-20 token interaction
-- Wraps Contract with the standard OpenZeppelin Cairo ERC-20 ABI baked in.
-- Provides both snake_case (Cairo standard) and camelCase method names.

local Contract = require("./Contract")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Standard OpenZeppelin Cairo ERC-20 ABI
--------------------------------------------------------------------------------

local ERC20_ABI: Contract.Abi = {
	-- name() -> felt252
	{
		type = "function",
		name = "name",
		inputs = {},
		outputs = { { name = "name", type = "core::felt252" } },
		state_mutability = "view",
	},
	-- symbol() -> felt252
	{
		type = "function",
		name = "symbol",
		inputs = {},
		outputs = { { name = "symbol", type = "core::felt252" } },
		state_mutability = "view",
	},
	-- decimals() -> u8
	{
		type = "function",
		name = "decimals",
		inputs = {},
		outputs = { { name = "decimals", type = "core::integer::u8" } },
		state_mutability = "view",
	},
	-- total_supply() -> u256
	{
		type = "function",
		name = "total_supply",
		inputs = {},
		outputs = { { name = "total_supply", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- balance_of(account) -> u256
	{
		type = "function",
		name = "balance_of",
		inputs = {
			{ name = "account", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "balance", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- allowance(owner, spender) -> u256
	{
		type = "function",
		name = "allowance",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "remaining", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- transfer(recipient, amount) -> bool
	{
		type = "function",
		name = "transfer",
		inputs = {
			{ name = "recipient", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- transfer_from(sender, recipient, amount) -> bool
	{
		type = "function",
		name = "transfer_from",
		inputs = {
			{ name = "sender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "recipient", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- approve(spender, amount) -> bool
	{
		type = "function",
		name = "approve",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- camelCase aliases (OZ ERC20CamelOnly compatibility)
	-- totalSupply() -> u256
	{
		type = "function",
		name = "totalSupply",
		inputs = {},
		outputs = { { name = "total_supply", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- balanceOf(account) -> u256
	{
		type = "function",
		name = "balanceOf",
		inputs = {
			{ name = "account", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "balance", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- transferFrom(sender, recipient, amount) -> bool
	{
		type = "function",
		name = "transferFrom",
		inputs = {
			{ name = "sender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "recipient", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
}

--------------------------------------------------------------------------------
-- ERC20 module
--------------------------------------------------------------------------------

local ERC20 = {}

--- Create a new ERC-20 contract instance with built-in ABI.
--- @param address -- hex contract address
--- @param provider -- RpcProvider instance
--- @param account -- optional Account for write operations
--- @return Contract instance with ERC-20 ABI
function ERC20.new(address: string, provider: any, account: any?): any
	if not address then
		error(StarknetError.validation("ERC20: address is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not provider then
		error(StarknetError.validation("ERC20: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	return Contract.new({
		abi = ERC20_ABI,
		address = address,
		provider = provider,
		account = account,
	})
end

--- Get the built-in ERC-20 ABI.
function ERC20.getAbi(): Contract.Abi
	return ERC20_ABI
end

return ERC20
