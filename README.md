# README

## Requirements

- Ruby 3.3.0
- PostgreSQL

## Prepare

```
bundle
cp config/database.yml.sample config/database.yml
cp config/cable.yml.sample config/cable.yml
EDITOR=cat bin/rails credentials:edit
rails db:create
```

## Run

```
rails db:reset && ./doc/poc.rb
```

Result is GraphViz dot

Put it to <https://dreampuf.github.io/GraphvizOnline/> to visualize

benchmarks

```
RAILS_ENV=production bundle exec rake benchmark:bm NUM=500
# batch create
RAILS_ENV=production bundle exec rake benchmark:bm NUM=5000 BATCH=100
```

## Showcase

- [db/migrate](db/migrate)
- [doc/poc.rb](doc/poc.rb)

## References

- https://blog.ethereum.org/2015/11/15/merkling-in-ethereum
- https://transparency.dev/verifiable-data-structures/
- https://transparency.dev/how-to-design-a-verifiable-system/
- https://github.com/google/trillian/tree/master/merkle
- https://github.com/google/trillian/tree/master/log
- https://github.com/transparency-dev/formats/blob/main/log/README.md#checkpoint-format
- https://github.com/transparency-dev
- https://datatracker.ietf.org/doc/html/rfc9162#name-merkle-trees
- https://aly.arriqaaq.com/merkle-tree-and-verifiable-data-structures/
- https://github.com/mpalmer/merkle-hash-tree
- https://www.derpturkey.com/merkle-tree-construction-and-proof-of-inclusion/
- https://github.com/OpenZeppelin/merkle-tree
- https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol
- https://medium.com/@colbyserpa/nostr-2-0-layer-2-off-chain-data-storage-b7d299078c60
