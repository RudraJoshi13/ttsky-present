![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# PRESENT-80 Lightweight Block Cipher (Tiny Tapeout)

PRESENT-80 encryption core (Saied H. Khayat's PresentCryptoEngine) behind a byte-wide register interface,
with a full scan chain (378 flip-flops, 99.60% stuck-at fault coverage with 242 patterns) inserted with
Difetto and hardened in Sky130 as a custom GDS (1x2 tiles, 50 MHz).

- [Project documentation](docs/info.md)
- Licence: Apache-2.0. The PRESENT core files are licensed under the MIT licence (see `src/LICENSE.present`).
