def rotr32(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def rotl32(x, n):
    return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF

def decrypt_64bit_pair(l, r, subkeys):
    # EXACT REVERSE of your Lua encrypt_block round
    for i in range(43, -1, -1):  # 43→0 (44 rounds)
        # Undo: l = rotl64(l,8) ^ r
        l = rotr32(l, 8) ^ r  
        
        # Undo: r = r ^ subkeys[i]  
        r = r ^ subkeys[i]
        
        # Undo: r = rotr64(r,3) + l  
        r = (r - l) & 0xFFFFFFFFFFFFFFFF
        
        # Undo: implicit rotr3 before add (handled in subtraction)
    
    return l, r

# YOUR EXACT KEY SCHEDULE (from Lua)
def generate_subkeys():
    KEY_HEX = 0x0123456789ABCDEF
    k = [KEY_HEX]
    l = [0]
    
    for i in range(43):
        temp = rotr32(k[-1] >> 32, 3) + l[-1] ^ i  # High 32 bits
        temp = (temp << 32) | (k[-1] & 0xFFFFFFFF)  # Recombine
        k.append(temp)
        
        l_next = rotl32(l[-1], 8) ^ k[-1]
        l.append(l_next)
    
    return [ki & 0xFFFFFFFFFFFFFFFF for ki in k]

subkeys = generate_subkeys()

# YOUR CIPHERTEXT (first 16 bytes, fix spacing)
cipher_hex = "56 5c 30 31 45 3d 3f 53 52 70 40 6f 4e 5e 54 57 35 4b 63 37 6b 49 63 35 73 35 5f 62 7b 23 5b 6d 28 4f 6f"
cipher_bytes = bytes.fromhex(cipher_hex.replace(' ', ''))

# Split into two 64-bit words (matches Lua combine_two_words)
l = int.from_bytes(cipher_bytes[0:8], 'big')
r = int.from_bytes(cipher_bytes[8:16], 'big')

# DECRYPT
dec_l, dec_r = decrypt_64bit_pair(l, r, subkeys)

print(f"Ciphertext:  {l:016x} {r:016x}")
print(f"Plaintext:   {dec_l:016x} {dec_r:016x}")
print(f"Bytes:       {dec_l.to_bytes(8, 'big').hex()} {dec_r.to_bytes(8, 'big').hex()}")