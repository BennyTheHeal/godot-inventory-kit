class_name IKUid
extends RefCounted
## Generates instance ids for unique items (128 random bits, hex encoded).

static var _crypto: Crypto


static func generate() -> String:
	if _crypto == null:
		_crypto = Crypto.new()
	return _crypto.generate_random_bytes(16).hex_encode()
