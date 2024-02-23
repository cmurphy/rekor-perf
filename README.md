Rekor Performance Tester
========================

Scripts to repeatably gather performance metrics for index storage insertion and
retrieval in rekor.

Usage
-----

```
./run.sh <number of artifacts>
```

The number of artifacts will be proportional to the number of insertions and the
number of retrievals performed.

To change the index backend, edit `docker-compose.yml` to update the
`search_index.storage_provider` setting in rekor-server.
