<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

SPI Protocol (Mode 0 — CPOL=0, CPHA=0)

Data is sampled on the SCK rising edge (MOSI → shift register)
Data is shifted out on the SCK falling edge (MISO ← tx_shift MSB)
Transfers are 8 bits, MSB first

Double-flop synchroniser on SCK and SS — since SCK comes from an external master running asynchronously to the TT system clock, both signals are registered twice before use to prevent metastability.
Edge detection — rising/falling edges on SCK and SS are derived from the synchronised versions (sck_r1, sck_r2), making the design fully synchronous internally.
No true tri-state on MISO — GF26 digital outputs don't support Hi-Z, so MISO is simply driven low when SS is deasserted. The master will ignore it while SS is high anyway.

## How to test

Drive the SPI bus by using an external SPI module configured as master. 
## External hardware

External MCU/FPGA that is configured as SPI master
