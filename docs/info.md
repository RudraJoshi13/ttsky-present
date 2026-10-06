<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project puts the PRESENT block cipher on Tiny Tapeout. PRESENT (Bogdanov et al., CHES 2007) is a
lightweight cipher standardised in ISO/IEC 29192-2. The design uses the PRESENT-80 encryption core by
Saied H. Khayat ([saiedhk/PresentCryptoEngine](https://github.com/saiedhk/PresentCryptoEngine), MIT licence)
without changes: a 64-bit block, an 80-bit key and 31 rounds, one round per clock. It encrypts only.

Tiny Tapeout has 24 I/O pins, so a wrapper gives the core a byte-wide register interface. The key and
plaintext are written one byte at a time, an encryption is started with a control write, and the ciphertext is
read back one byte at a time. The wrapper captures the core's output when the 31 rounds finish, because the core
holds the ciphertext for one clock only.

| Pins | Function |
|------|----------|
| `ui[4:0]` | byte address |
| `ui[7]` | write strobe, active high (synchronised inside the chip) |
| `uio[7:0]` | write data byte (all `uio` pins are inputs) |
| `uo[7:0]` | read data byte at the selected address |

Multi-byte values are stored most significant byte first.

| Address | Register | Access |
|---------|----------|--------|
| `0x00` to `0x09` | Key: `0x00` holds bits 79:72, `0x09` holds bits 7:0 | read and write |
| `0x0A` to `0x11` | Plaintext: `0x0A` holds bits 63:56, `0x11` holds bits 7:0 | read and write |
| `0x12` to `0x19` | Ciphertext: `0x12` holds bits 63:56, `0x19` holds bits 7:0 | read only |
| `0x1A` | Control and status: write bit 0 = 1 to start; read bit 0 = busy, bit 1 = done | read and write |
| `0x1B` | ID, reads `0x50` | read only |
| `0x1C` to `0x1F` | unused, read 0 | |

A start is ignored while busy. Busy lasts 32 clock cycles; then the ciphertext register is updated, busy
clears and done is set. Done stays set until the next start. Reset clears all registers to 0.

## How to test

1. Reset the chip.
2. Write the 10 key bytes to addresses `0x00` to `0x09`.
3. Write the 8 plaintext bytes to addresses `0x0A` to `0x11`.
4. Write `0x01` to address `0x1A`.
5. Read address `0x1A` until it reads `0x02` (done, not busy).
6. Read the 8 ciphertext bytes from addresses `0x12` to `0x19`.

To write a byte: set `ui[4:0]` to the address and `uio[7:0]` to the data, raise `ui[7]`, hold it for at
least 3 clock cycles, then lower it. To read a byte: set `ui[4:0]` to the address and read `uo[7:0]` 2 or more
clock cycles later.

Test vectors from the PRESENT paper (Appendix I):

| Plaintext | Key | Ciphertext |
|-----------|-----|------------|
| `0000000000000000` | `00000000000000000000` | `5579c1387b228445` |
| `0000000000000000` | `ffffffffffffffffffff` | `e72c46c0f5945049` |
| `ffffffffffffffff` | `00000000000000000000` | `a112ffc72f68417b` |
| `ffffffffffffffff` | `ffffffffffffffffffff` | `3333dcd3213210d2` |

## External hardware

None. The RP2040 on the Tiny Tapeout demo board can drive `ui` and `uio` and read `uo`.
