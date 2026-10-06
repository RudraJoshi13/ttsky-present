# SPDX-FileCopyrightText: © 2026 Rudra Joshi
# SPDX-License-Identifier: Apache-2.0
#
# cocotb test for tt_um_rj_present. Everything goes through the pins:
# write key and plaintext, start, poll status, read the ciphertext.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Address map (see docs/info.md)
A_KEY = 0x00     # 10 bytes, most significant first
A_PT = 0x0A      # 8 bytes, most significant first
A_CT = 0x12      # 8 bytes, read only
A_CTRL = 0x1A    # write bit 0 = start; read bit 0 = busy, bit 1 = done
A_ID = 0x1B      # reads 0x50
STROBE = 0x80    # ui_in[7]

# The four official vectors from the PRESENT paper (Appendix I):
# (plaintext, key, ciphertext)
OFFICIAL = [
    (0x0000000000000000, 0x00000000000000000000, 0x5579C1387B228445),
    (0x0000000000000000, 0xFFFFFFFFFFFFFFFFFFFF, 0xE72C46C0F5945049),
    (0xFFFFFFFFFFFFFFFF, 0x00000000000000000000, 0xA112FFC72F68417B),
    (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFFFFFF, 0x3333DCD3213210D2),
]

# Extra vectors: the core author's testbench inputs. Ciphertexts were
# checked against the Oosterlynck/Teuwen Python reference (25 of 25 match).
EXTRA = [
    (0x834349FD8E99A23B, 0x00000000000000000000, 0xCB69CB8566E0B8AC),
    (0x9281DCB8A883A38C, 0x3014F4D8C37D9CC7E689, 0x3A21B91C91C0C6D4),
    (0xD392F4EC58356AEB, 0x88239F8276EC927C8DEC, 0xF362A13CFA39624A),
    (0x3E5380018FC28D70, 0x610DCECCE9A001117102, 0x1A80C3315CC93D19),
    (0x0000000000000000, 0x01F43BBC9B2001545339, 0xC0C79D5FBCF1A7C0),
]


async def write_byte(dut, addr, value):
    """Set address and data, raise the strobe for 4 clocks, lower it."""
    dut.ui_in.value = addr
    dut.uio_in.value = value
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = STROBE | addr
    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = addr
    await ClockCycles(dut.clk, 2)


async def read_byte(dut, addr):
    """Set the address, wait 2 clocks, read uo_out."""
    dut.ui_in.value = addr
    await ClockCycles(dut.clk, 2)
    return dut.uo_out.value.to_unsigned()


async def write_bytes(dut, base, value, nbytes):
    for i in range(nbytes):
        await write_byte(dut, base + i, (value >> (8 * (nbytes - 1 - i))) & 0xFF)


async def read_bytes(dut, base, nbytes):
    value = 0
    for i in range(nbytes):
        value = (value << 8) | await read_byte(dut, base + i)
    return value


async def encrypt(dut, pt, key):
    await write_bytes(dut, A_KEY, key, 10)
    await write_bytes(dut, A_PT, pt, 8)
    assert await read_bytes(dut, A_KEY, 10) == key, "key readback"
    assert await read_bytes(dut, A_PT, 8) == pt, "plaintext readback"
    await write_byte(dut, A_CTRL, 0x01)          # start
    for _ in range(100):
        if await read_byte(dut, A_CTRL) == 0x02:  # done = 1, busy = 0
            break
    else:
        assert False, "timeout waiting for done"
    return await read_bytes(dut, A_CT, 8)


@cocotb.test()
async def test_present(dut):
    dut._log.info("Start")
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz, as in info.yaml
    cocotb.start_soon(clock.start())

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("After reset: ID, status and ciphertext")
    assert await read_byte(dut, A_ID) == 0x50
    assert await read_byte(dut, A_CTRL) == 0x00
    assert await read_bytes(dut, A_CT, 8) == 0

    for pt, key, ct in OFFICIAL + EXTRA:
        got = await encrypt(dut, pt, key)
        dut._log.info(f"pt={pt:016x} key={key:020x} ct={got:016x} expected={ct:016x}")
        assert got == ct
