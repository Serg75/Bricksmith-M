# Connectivity test fixtures

Two small libraries the tests read from disk. Both are unchanged copies.

## `ldraw/` — LDraw parts

The parts below, plus every subpart and primitive they reference:

    3001 3003 3004 3005 3020 3022 3023b 3024 3037 3040b 3062b 3069b 3070b
    3298 3660 3665 3794b 3941 4073 4733 6141 10a 15573 44728 87087 99207

Copied from the official LDraw parts library. © LDraw.org contributors,
licensed under CC BY 2.0 or CC BY 4.0 as stated in each file's header. See
`CAreadme.txt` and https://www.ldraw.org/legal-info.

## `shadow/` — LDCad shadow library

The shadow files for the same parts, subparts and primitives, from
https://github.com/RolandMelkert/LDCadShadowLibrary at commit `9b1131f`
(2026-09-10). © LDCad Shadow Library contributors, licensed under CC BY-SA 4.0.
See `shadow/LICENSE.md`.
