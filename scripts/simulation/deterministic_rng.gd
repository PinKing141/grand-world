class_name DeterministicRng
extends RefCounted

const MASK_32 := 0xFFFFFFFF
const NON_ZERO_FALLBACK := 0x6D2B79F5


static func stream_seed(campaign_seed: int, stream_name: String) -> int:
	# FNV-1a gives named streams stable seeds without relying on String.hash().
	var value := 2166136261
	for byte in stream_name.to_utf8_buffer():
		value = ((value ^ int(byte)) * 16777619) & MASK_32
	value = (value ^ (campaign_seed & MASK_32)) & MASK_32
	return value if value != 0 else NON_ZERO_FALLBACK


static func advance(state: int) -> int:
	var value := state & MASK_32
	if value == 0:
		value = NON_ZERO_FALLBACK
	value = (value ^ ((value << 13) & MASK_32)) & MASK_32
	value = (value ^ (value >> 17)) & MASK_32
	value = (value ^ ((value << 5) & MASK_32)) & MASK_32
	return value if value != 0 else NON_ZERO_FALLBACK


static func unit_float(state: int) -> float:
	return float(state & MASK_32) / 4294967296.0
