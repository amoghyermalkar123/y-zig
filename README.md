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
  [X] more tests for remote update integ
  [X] final phase 1 review
  [X] replay system (debug util) (completed phase 1 level of the util, this should be matured as need and understanding grows)
  [X] review memory

Phase 2: add support for a proper string content
- Items:
  [X] implement block splitting
  [X] marker updating everytime a new thing happens
  [X] scrap replay system

Phase 3:
  [] make `integrate` work for both local and remote blocks
  [] check for api and algorithm improvements

Phase 4: Deletions (only to be done when insertion is stable)
- support pending delete set queue and retry
- support GC

Phase 5: Build on top of it:
- state vector based delta awareness
  - remote peer update decoding
  - performing integration on remote blocks
  - behavior tests
- more comprehensive/ robust tests (tests are unreadable)
- snapshoting system
- using the snapshot system for sophisticated replay system for
  educational purposes

This project is heavy WIP

non triaged
  [] abstraction based dev
    - block store should be a good reusable abstraction not constrained to a type
    - type operator should build on top of a block store
    - revisit marker system in terms of faster and efficient ops
  [] support moved ranges

