--!strict
-- ERC721: Pre-built contract interface for ERC-721 NFT interaction
-- Wraps Contract with the standard OpenZeppelin Cairo ERC-721 ABI baked in.
-- Provides both snake_case (Cairo standard) and camelCase method names.

local Contract = require("./Contract")
local PresetFactory = require("./PresetFactory")

--------------------------------------------------------------------------------
-- Standard OpenZeppelin Cairo ERC-721 ABI
--------------------------------------------------------------------------------

local ERC721_ABI: Contract.Abi = {
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
	-- balance_of(owner) -> u256
	{
		type = "function",
		name = "balance_of",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "balance", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- owner_of(token_id) -> ContractAddress
	{
		type = "function",
		name = "owner_of",
		inputs = {
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = { { name = "owner", type = "core::starknet::contract_address::ContractAddress" } },
		state_mutability = "view",
	},
	-- get_approved(token_id) -> ContractAddress
	{
		type = "function",
		name = "get_approved",
		inputs = {
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = { { name = "approved", type = "core::starknet::contract_address::ContractAddress" } },
		state_mutability = "view",
	},
	-- is_approved_for_all(owner, operator) -> bool
	{
		type = "function",
		name = "is_approved_for_all",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "operator", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "approved", type = "core::bool" } },
		state_mutability = "view",
	},
	-- transfer_from(from, to, token_id)
	{
		type = "function",
		name = "transfer_from",
		inputs = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = {},
		state_mutability = "external",
	},
	-- approve(to, token_id)
	{
		type = "function",
		name = "approve",
		inputs = {
			{ name = "to", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = {},
		state_mutability = "external",
	},
	-- set_approval_for_all(operator, approved)
	{
		type = "function",
		name = "set_approval_for_all",
		inputs = {
			{ name = "operator", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "approved", type = "core::bool" },
		},
		outputs = {},
		state_mutability = "external",
	},
	-- camelCase aliases (OZ ERC721CamelOnly compatibility)
	-- balanceOf(owner) -> u256
	{
		type = "function",
		name = "balanceOf",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "balance", type = "core::integer::u256" } },
		state_mutability = "view",
	},
	-- ownerOf(token_id) -> ContractAddress
	{
		type = "function",
		name = "ownerOf",
		inputs = {
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = { { name = "owner", type = "core::starknet::contract_address::ContractAddress" } },
		state_mutability = "view",
	},
	-- getApproved(token_id) -> ContractAddress
	{
		type = "function",
		name = "getApproved",
		inputs = {
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = { { name = "approved", type = "core::starknet::contract_address::ContractAddress" } },
		state_mutability = "view",
	},
	-- isApprovedForAll(owner, operator) -> bool
	{
		type = "function",
		name = "isApprovedForAll",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "operator", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = { { name = "approved", type = "core::bool" } },
		state_mutability = "view",
	},
	-- transferFrom(from, to, token_id)
	{
		type = "function",
		name = "transferFrom",
		inputs = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "token_id", type = "core::integer::u256" },
		},
		outputs = {},
		state_mutability = "external",
	},
	-- setApprovalForAll(operator, approved)
	{
		type = "function",
		name = "setApprovalForAll",
		inputs = {
			{ name = "operator", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "approved", type = "core::bool" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

return PresetFactory.create(ERC721_ABI)
