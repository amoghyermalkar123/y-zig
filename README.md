### Y-Zig

Short for Yata-Zig is my project to understand CRDTs in depth.
This is inspired by the academic paper here - https://www.researchgate.net/publication/310212186_Near_Real-Time_Peer-to-Peer_Shared_Editing_on_Extensible_Data_Types

and tries to be a mini-port of the Yjs implementation of the same paper here -
https://github.com/yjs/yjs
focusing only on the text based data structure as of now.

## Roadmap

### This is a priority list arranged from high to low
Phase 1: Only focus on Single character content
- Items:
  [X] implement integration logic (local insert)
  [X] basic state vector impl for remote block integ

Phase 2: add support for a proper string content
- Items:
  - implement block splitting
  - TBD

Phase 3: Build on top of it:
- state vector based delta awareness
  - remote peer update decoding
  - performing integration on remote blocks
- support GC
- support moved ranges (????)
- update apply logic (pending, pending delete set)

Phase 4:
- memory memory memory :)

This project is heavy WIP
