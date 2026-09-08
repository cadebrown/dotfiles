# Fixed evidence packet

Source URLs were checked on 2026-09-07. These are paraphrased extracts for a controlled research task, not full documentation. Base the answer on these facts and identify any inference.

## SQLite: Write-Ahead Logging

https://www.sqlite.org/wal.html

- WAL readers and a writer can proceed concurrently; a database still has only one writer at a time.
- WAL normally relies on shared memory. All participating processes must be on the same host; this mode does not work across a network filesystem.
- Committed transactions can be present in the WAL file before their pages are copied to the main database during a checkpoint.
- A long-lived reader can limit checkpoint progress. SQLite normally initiates an automatic checkpoint when the WAL reaches a configured threshold (default 1000 pages).
- The documentation includes version-specific caveats and a WAL-reset bug advisory. This packet does not establish that an arbitrary deployed SQLite version is free of that issue.

## SQLite: Online Backup API

https://www.sqlite.org/backup.html

- The Online Backup API copies a live database to another database while allowing concurrent access, using limited locking while each backup step operates.
- A successful complete backup contains a consistent snapshot. Incremental steps can restart in response to intervening writes, so contention affects progress.
- The page also describes VACUUM INTO as a way to produce a separate compact copy of a live database.

## Project facts

- A normal deployment has one desktop and several local indexing workers.
- Some users have an NFS home shared between macOS and Linux machines.
- Nobody has measured write contention, transaction length, or backup latency on the target workloads yet.
