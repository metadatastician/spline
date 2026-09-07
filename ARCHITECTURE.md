<!-- SPDX-License-Identifier: MPL-2.0 -->
# Spline architecture

Spline owns the alignment between Groove session semantics and consumer-owned
wire planes. It is not a serializer or a second copy of Burble's schema.

- Control: reliable, ordered Bebop voice-signal messages.
- Media: WebRTC/RTP, independent of control-plane delivery.
- Groove owns discovery, negotiation, signed manifest records and opaque tokens.
- Cleave owns local lifetime, rank and posture. These witnesses must not be
  encoded into Spline's wire representation.
- Burble owns its schema and encoder; Gossamer owns an independent decoder.

The authoritative mapping is [voice-signal-plane.adoc](docs/alignment/voice-signal-plane.adoc).
Groove's alignment checker verifies its recorded examples against that mapping;
a matching example is not a proof of all encoder/decoder inputs.

ADR 0005 deliberately prohibits a `src/` implementation until all four promotion
criteria have evidence. The live typed-token pairing criterion remains open.
See [beta acceptance](docs/status/BETA-ACCEPTANCE.adoc) for the capture contract.
No ABI, FFI, server, database or deployment architecture is claimed here.
