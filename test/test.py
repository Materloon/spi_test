# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

async def spi_send_byte(dut, byte_to_send):
    """Send one byte MSB-first in SPI Mode 0, return received MISO byte."""
    received = 0
    for i in range(7, -1, -1):
        dut.ui_in.value = (dut.ui_in.value & ~0x04) | (((byte_to_send >> i) & 1) << 2)  # MOSI
        await Timer(50, units="ns")

        # Rising edge — slave samples MOSI
        dut.ui_in.value = dut.ui_in.value | 0x01   # SCK high
        await Timer(50, units="ns")

        miso = (dut.uo_out.value >> 0) & 1
        received = (received << 1) | miso

        # Falling edge — slave shifts MISO
        dut.ui_in.value = dut.ui_in.value & ~0x01  # SCK low
        await Timer(50, units="ns")

    return received

@cocotb.test()
async def test_project(dut):
    cocotb.log.info("Start")

    # Start system clock at 100 MHz
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    cocotb.log.info("Reset")
    dut.ena.value     = 1
    dut.ui_in.value   = 0b00000010  # SS_N=1, SCK=0, MOSI=0
    dut.uio_in.value  = 0
    dut.rst_n.value   = 0
    await Timer(90, units="ns")
    dut.rst_n.value   = 1
    await Timer(10, units="ns")

    cocotb.log.info("Test SPI loopback")

    # --- Transaction 1: send 0xB7, expect MISO=0xA5 (default tx_byte) ---
    dut.ui_in.value = dut.ui_in.value & ~0x02  # SS_N low (assert)
    await Timer(200, units="ns")

    miso_rx = await spi_send_byte(dut, 0xB7)

    dut.ui_in.value = dut.ui_in.value | 0x02   # SS_N high (deassert)
    await Timer(200, units="ns")

    cocotb.log.info(f"T1 MISO: 0x{miso_rx:02X} (expected 0xA5)")
    assert miso_rx == 0xA5, f"T1 MISO mismatch: got 0x{miso_rx:02X}, expected 0xA5"

    # --- Transaction 2: send 0x3C, expect MISO=0xB7 (loopback from T1) ---
    dut.ui_in.value = dut.ui_in.value & ~0x02  # SS_N low
    await Timer(200, units="ns")

    miso_rx = await spi_send_byte(dut, 0x3C)

    dut.ui_in.value = dut.ui_in.value | 0x02   # SS_N high
    await Timer(200, units="ns")

    cocotb.log.info(f"T2 MISO: 0x{miso_rx:02X} (expected 0xB7)")
    assert miso_rx == 0xB7, f"T2 MISO mismatch: got 0x{miso_rx:02X}, expected 0xB7"

    cocotb.log.info("All tests passed!")
