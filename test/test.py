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


# ---------------------------------------------------------------------
# Additional tests for coverage (each checks one behaviour)
# ---------------------------------------------------------------------

async def pulse_reset(dut):
    """Hold rst_n low for 10 clocks, release it, wait 2 clocks."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def start_clock_and_reset(dut):
    """Start a 50 MHz clock, set the inputs to idle and reset."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await pulse_reset(dut)


async def check_cleared(dut):
    """Every register reads as after reset; the ID is unchanged."""
    assert await read_bytes(dut, A_KEY, 10) == 0, "key not cleared"
    assert await read_bytes(dut, A_PT, 8) == 0, "plaintext not cleared"
    assert await read_bytes(dut, A_CT, 8) == 0, "ciphertext not cleared"
    assert await read_byte(dut, A_CTRL) == 0x00, "status not cleared"
    assert await read_byte(dut, A_ID) == 0x50, "ID changed"


@cocotb.test()
async def test_reset_clears_state(dut):
    """Reset after an encryption and reset during one both clear all
    registers, and the next encryption is still correct."""
    await start_clock_and_reset(dut)

    # 1) Reset after a finished encryption. This vector's ciphertext has
    #    bits 16 and 55 set, so the reset also takes them from 1 to 0.
    pt, key, ct = EXTRA[4]
    assert await encrypt(dut, pt, key) == ct
    await pulse_reset(dut)
    await check_cleared(dut)
    dut._log.info("reset after encryption: all registers cleared")

    # 2) Reset while busy: load, start, confirm busy, then reset.
    pt, key, ct = OFFICIAL[3]
    await write_bytes(dut, A_KEY, key, 10)
    await write_bytes(dut, A_PT, pt, 8)
    await write_byte(dut, A_CTRL, 0x01)
    assert await read_byte(dut, A_CTRL) == 0x01, "expected busy before reset"
    await pulse_reset(dut)
    await check_cleared(dut)
    dut._log.info("reset during encryption: all registers cleared")

    # 3) The design still works normally after both resets.
    pt, key, ct = OFFICIAL[0]
    assert await encrypt(dut, pt, key) == ct
    dut._log.info("encryption after resets: correct")


@cocotb.test()
async def test_register_rules(dut):
    """Unused addresses read 0; writes to read-only and unused addresses
    are ignored; a start write needs bit 0; a held strobe starts only
    once; the unused inputs ui_in[5] and ui_in[6] have no effect."""
    await start_clock_and_reset(dut)
    pt, key, ct = OFFICIAL[1]
    assert await encrypt(dut, pt, key) == ct  # known state: done = 1

    # 1) Unused addresses read as 0.
    for a in range(0x1C, 0x20):
        assert await read_byte(dut, a) == 0x00, f"address {a:#04x} not 0"

    # 2) Writes to ciphertext, ID and unused addresses are ignored.
    for a in list(range(A_CT, A_CT + 8)) + [A_ID] + list(range(0x1C, 0x20)):
        await write_byte(dut, a, 0xA5)
    assert await read_bytes(dut, A_CT, 8) == ct, "ciphertext changed by a write"
    assert await read_byte(dut, A_ID) == 0x50, "ID changed by a write"
    for a in range(0x1C, 0x20):
        assert await read_byte(dut, a) == 0x00, "unused address changed"
    assert await read_bytes(dut, A_KEY, 10) == key, "key changed"
    assert await read_bytes(dut, A_PT, 8) == pt, "plaintext changed"
    assert await read_byte(dut, A_CTRL) == 0x02, "status changed"
    dut._log.info("unused reads are 0, read-only and unused writes ignored")

    # 3) A control write with bit 0 = 0 does not start an encryption.
    await write_byte(dut, A_CTRL, 0xFE)
    assert await read_byte(dut, A_CTRL) == 0x02, "started without bit 0"
    dut._log.info("start write without bit 0: no start")

    # 4) Strobe held high on a start for 100 clocks: busy rises once.
    dut.uio_in.value = 0x01
    dut.ui_in.value = STROBE | A_CTRL
    rises, prev = 0, 0
    for _ in range(100):
        await ClockCycles(dut.clk, 1)
        busy = dut.uo_out.value.to_unsigned() & 1
        if busy and not prev:
            rises += 1
        prev = busy
    dut.ui_in.value = A_CTRL
    await ClockCycles(dut.clk, 2)
    assert rises == 1, f"busy rose {rises} times with the strobe held"
    assert await read_byte(dut, A_CTRL) == 0x02, "not done after held strobe"
    assert await read_bytes(dut, A_CT, 8) == ct, "wrong ciphertext after held strobe"
    dut._log.info("strobe held 100 clocks: exactly one encryption")

    # 5) The unused inputs ui_in[5] and ui_in[6] have no effect.
    dut.ui_in.value = 0x60 | A_ID
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value.to_unsigned() == 0x50, "ui_in[6:5] changed the read"
    dut.ui_in.value = A_ID
    await ClockCycles(dut.clk, 2)
    dut._log.info("ui_in[5] and ui_in[6] ignored")


async def wait_done(dut):
    """Poll the status register until done = 1 and busy = 0."""
    for _ in range(100):
        if await read_byte(dut, A_CTRL) == 0x02:
            return
    assert False, "timeout waiting for done"


@cocotb.test()
async def test_busy_protection(dut):
    """While an encryption runs, a second start is ignored and key and
    plaintext writes do not change its result. The new values are kept
    and used by the next start."""
    await start_clock_and_reset(dut)
    pt, key, ct = EXTRA[1]
    await write_bytes(dut, A_KEY, key, 10)
    await write_bytes(dut, A_PT, pt, 8)
    await write_byte(dut, A_CTRL, 0x01)  # start

    # While busy: a second start, a new top key byte and plaintext byte.
    await write_byte(dut, A_CTRL, 0x01)
    await write_byte(dut, A_KEY, 0x5A)
    await write_byte(dut, A_PT, 0xC3)
    assert await read_byte(dut, A_CTRL) == 0x01, "not busy: writes did not land during the encryption"

    # The running encryption is unaffected.
    await wait_done(dut)
    assert await read_bytes(dut, A_CT, 8) == ct, "result changed by writes during encryption"
    dut._log.info("writes and a second start while busy: result unchanged")

    # The new values were stored and the next start uses them.
    # Expected ciphertext from the Oosterlynck/Teuwen Python reference.
    key2, pt2, ct2 = 0x5A14F4D8C37D9CC7E689, 0xC381DCB8A883A38C, 0x18D24C5631480B99
    assert await read_bytes(dut, A_KEY, 10) == key2, "new key byte not stored"
    assert await read_bytes(dut, A_PT, 8) == pt2, "new plaintext byte not stored"
    await write_byte(dut, A_CTRL, 0x01)
    await wait_done(dut)
    assert await read_bytes(dut, A_CT, 8) == ct2, "wrong result with the new values"
    dut._log.info("next start uses the new key and plaintext: correct")
