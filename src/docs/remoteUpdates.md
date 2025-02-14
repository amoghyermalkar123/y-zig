## How remote updates are read and integrated in local document
- get transaction
- get the underlying struct store
- de serialize the binary update we receive from a peer
- start integrating per-client block list
- retry previously un-integrated blocks into block store
- un-integrated blocks are added to pending queue and will be retried in the next integration call
- same for delete set
