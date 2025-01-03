### Y-Zig

Short for Yata-Zig is my project to understand CRDTs in depth.
This is inspired by the academic paper here - https://www.researchgate.net/publication/310212186_Near_Real-Time_Peer-to-Peer_Shared_Editing_on_Extensible_Data_Types

and tries to be a mini-port of the Yjs implementation of the same paper here -
https://github.com/yjs/yjs

### Roadmap
## This is a priority list arranged from high to low
[*] implement integration logic (local insert)
- state vector based delta awareness
  - remote peer update decoding
  - performing integration on remote blocks
- support moved ranges (????)
- update apply logic (pending, pending delete set)


This project is heavy WIP
