<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project puts the PRESENT block cipher on Tiny Tapeout. PRESENT (Bogdanov et al., CHES 2007) is a
lightweight cipher standardised in ISO/IEC 29192-2. The design uses the PRESENT-80 encryption core by
Saied H. Khayat ([saiedhk/PresentCryptoEngine](https://github.com/saiedhk/PresentCryptoEngine), MIT licence):
a 64-bit block, an 80-bit key and 31 rounds, one round per clock. It encrypts only. The cipher logic is
unchanged; the only edit is that the core's simulation-only debug print is switched off (line 26 of
`present_encrypt.v`), because the hardening flow's Verilog reader rejects the `$time` it uses.

Tiny Tapeout has 24 I/O pins, so a wrapper gives the core a byte-wide register interface. The key and
plaintext are written one byte at a time, an encryption is started with a control write, and the ciphertext is
read back one byte at a time. The wrapper captures the core's output when the 31 rounds finish, because the core
holds the ciphertext for one clock only.

| Pins | Function |
|------|----------|
| `ui[4:0]` | byte address |
| `ui[7]` | write strobe, active high (synchronised inside the chip) |
| `ui[5]` | scan enable, active high. Keep it low in normal use |
| `ui[6]` | scan in (ignored while `ui[5]` is low) |
| `uio[7:0]` | write data byte. All `uio` pins are inputs, except `uio[0]`, which becomes the scan output while `ui[5]` is high |
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

Keep `ui[5]` (scan enable) low for normal use.

1. Reset the chip.
2. Write the 10 key bytes to addresses `0x00` to `0x09`.
3. Write the 8 plaintext bytes to addresses `0x0A` to `0x11`.
4. Write `0x01` to address `0x1A`.
5. Read address `0x1A` until it reads `0x02` (done, not busy).
6. Read the 8 ciphertext bytes from addresses `0x12` to `0x19`.

To write a byte: set `ui[4:0]` to the address and `uio[7:0]` to the data, raise `ui[7]`, hold it for at
least 3 clock cycles with the address and data unchanged, then lower it. Keep `ui[7]` low for at least 3
clock cycles before the next write. To read a byte: set `ui[4:0]` to the address and read `uo[7:0]` 2 or more
clock cycles later.

Test vectors from the PRESENT paper (Appendix I):

| Plaintext | Key | Ciphertext |
|-----------|-----|------------|
| `0000000000000000` | `00000000000000000000` | `5579c1387b228445` |
| `0000000000000000` | `ffffffffffffffffffff` | `e72c46c0f5945049` |
| `ffffffffffffffff` | `00000000000000000000` | `a112ffc72f68417b` |
| `ffffffffffffffff` | `ffffffffffffffffffff` | `3333dcd3213210d2` |

## Scan chain test

The design also contains a scan chain for manufacturing test (design for test). It was inserted with
Difetto (OpenROAD scan insertion with placement-aware chain ordering), so the layout is hardened locally
and submitted as a custom GDS. All 378 flip-flops are in one chain. The chain is shifted on the normal
clock `clk`. Scan in is `ui[6]`, scan out is `uio[0]`, and scan enable is `ui[5]`. While `ui[5]` is
high, `uio[0]` is driven by the chip; while it is low, `uio[0]` is the normal `wdata[0]` input.

One test pattern is applied as follows:

1. Keep `rst_n` high. Release `uio[0]` (make it an input on the RP2040), then set `ui[5]` high.
2. Shift the 378 flip-flop values in on `ui[6]`, one per rising clock edge.
3. Set `ui[5]` low, then drive `uio[0]` again, and set the other `ui` and `uio` inputs from the pattern.
   Check `uo[7:0]` against the expected values.
4. Give one clock (the capture clock).
5. Release `uio[0]`, set `ui[5]` high, and shift the 378 captured values out on `uio[0]` while the next
   pattern shifts in.

After the last pattern, set `ui[5]` low and reset the chip before normal use, because the scan test leaves
arbitrary values in the registers.

The test patterns were generated with quaigh: 242 patterns give 99.60% coverage of single stuck-at
faults (6,671 of 6,698 collapsed faults). This number covers the logic after scan insertion; it does not
include delay faults or the buffers added later during placement and routing, including three buffers added
after routing to keep every net within the 0.75 ns slew limit. The chain itself is checked separately by
shifting a known bit stream through it. All 242 patterns were replayed on the final routed gate-level
netlist in simulation with no mismatches.

## External hardware

None. The RP2040 on the Tiny Tapeout demo board can drive `ui` and `uio` and read `uo`.
