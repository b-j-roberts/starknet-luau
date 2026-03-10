--!strict
-- ERC20: Pre-built contract interface for ERC-20 token interaction
-- Wraps Contract with the standard OpenZeppelin Cairo ERC-20 ABI baked in.
-- Provides both snake_case (Cairo standard) and camelCase method names.

local Contract = require("./Contract")
local PresetFactory = require("./PresetFactory")

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
	-- increase_allowance(spender, added_value) -> bool
	{
		type = "function",
		name = "increase_allowance",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "added_value", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- decrease_allowance(spender, subtracted_value) -> bool
	{
		type = "function",
		name = "decrease_allowance",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "subtracted_value", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- Events
	-- Transfer(from, to, value)
	{
		type = "event",
		name = "Transfer",
		kind = "struct",
		members = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "value", type = "core::integer::u256", kind = "data" },
		},
	},
	-- Approval(owner, spender, value)
	{
		type = "event",
		name = "Approval",
		kind = "struct",
		members = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "value", type = "core::integer::u256", kind = "data" },
		},
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
	-- increaseAllowance(spender, addedValue) -> bool
	{
		type = "function",
		name = "increaseAllowance",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "added_value", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	-- decreaseAllowance(spender, subtractedValue) -> bool
	{
		type = "function",
		name = "decreaseAllowance",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "subtracted_value", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
}

return PresetFactory.create(ERC20_ABI)
