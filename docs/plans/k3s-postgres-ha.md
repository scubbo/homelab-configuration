# k3s PostgreSQL availability

**Status: investigation complete; implementation choice pending with Jack.** This is a dependency/recovery workstream of the [epsilon Debian upgrade](epsilon-debian-upgrade.md) and [Proxmox installation](proxmox-installation.md). The [live datastore documentation](../k3s-ha-postgres/README.md) describes the running singleton.

## Observed state

On 2026-10-04, read-only SQL/container inspection found PostgreSQL **17.5**, image ID `sha256:445ed93b882fd8274de6c88ed5c6efea0743e112d232d87a8bc0b9b8817e8316`, bind-mounted data at `/home/scubbo/k3s-ha-postgres-data`, database `kubernetes` about 67 MB. No replicas are connected. `wal_level=replica`, `max_wal_senders=10`, `archive_mode=off`, `synchronous_commit=on`, and no synchronous standby names. Data checksums and `wal_log_hints` are off.

Scheduled SQL dumps on galactus are present, most recently `2026-10-01T05:00:01.sql`. An isolated restore using the exact existing image succeeded on 2026-10-04: 5,529 kine rows, maximum revision 277229140, and no SQL errors. The test container has no network, published ports, production data mount, or automatic restart. It is stopped and retained for Jack's inspection; the [catalogue](../asset-catalogue.md) records its location. This proves the SQL artifact can restore; it does not test server-token recovery, PostgreSQL HA, or reboot survival.

## Bootstrap and failure-domain requirements

- The database and its failover coordination must start without the Kubernetes cluster **whose state they store**. Putting this datastore in CloudNative-PG on that same cluster creates a recovery/bootstrap dependency loop. A separate independent Kubernetes cluster could host it, but requires another platform to recover.
- Put database instances on distinct physical hosts. Two guests on epsilon provide process separation but both disappear during epsilon maintenance. A replica on culex survives epsilon reboots; a witness/coordination service must also survive them.
- Use independent local data volumes, not one PostgreSQL data directory mounted read-write on multiple machines. Replication coordinates the contents; a shared NAS mount is not PostgreSQL failover logic and adds its own failure domain.
- Preserve **one writable primary**. Replication alone does not fence a failed/partitioned primary or direct clients to the promoted server.
- A stable writer endpoint must also be available independently of this cluster. Use redundant TCP proxies with primary-role health checks and a reviewed virtual IP/routing solution, or a proved driver-level multi-host mechanism. k3s/kine uses the Go `lib/pq` PostgreSQL driver; do not assume a libpq `target_session_attrs`/multi-host connection string works in it. TCP forwarding avoids prepared-statement pooling incompatibilities.
- Backups, WAL/PITR if adopted, cluster token, credentials, endpoint configuration, and recovery instructions remain required. Replication can propagate mistakes/deletions.

## Practical options

| Option | Placement and failover | Tradeoff |
| --- | --- | --- |
| Streaming standby + manual planned switchover | PostgreSQL 17 instances on epsilon and culex, independent systemd/container lifecycle; operator fences source, confirms replay, promotes standby, redirects the writer endpoint | Smallest way to practice planned node maintenance. Unexpected failure is operator recovery, not automatic HA. |
| Patroni + independent etcd quorum | PostgreSQL on epsilon/culex (third data node if available); 3 etcd members on distinct physical machines such as epsilon, culex, rasnu1; independent role-aware writer endpoint | Established automatic failover, but introduces quorum management, fencing/watchdog, credentials/TLS, and proxy/VIP recovery. A third witness is not a third database copy. |
| pg_auto_failover | Data nodes on epsilon/culex plus independent monitor on a third host; reviewed writer routing | Smaller coordination model. Monitor failure preserves running service but prevents responding to another failure until recovered. Replication-mode degradation must be understood. |
| Embedded etcd for k3s | Three server nodes on independent physical hosts | Removes external SQL dependencies for a redesigned cluster; migrating existing external PostgreSQL state is a separate project, not a connection-string edit. Not required by this plan. |

For **planned maintenance first**, a streaming standby with rehearsed manual switchover is a reasonable first stage. For **automatic PostgreSQL HA**, Patroni is the proposed candidate, subject to Jack agreeing placement and durability/availability policy. Do not make HA rollout a surprise prerequisite for the accepted-downtime Debian upgrade: evaluate it now, then either rehearse/deploy separately or proceed with proved singleton recovery and documented downtime.

### Durability versus writes during maintenance

Asynchronous replication can lose committed state during an unexpected primary failure. For k3s datastore revisions, prefer a design that avoids losing acknowledged transactions and prove API behavior across promotion.

Two data nodes with strict synchronous replication block writes when the other is unavailable. A third **data** node on a third physical machine is needed to retain strict multi-node durability and writes while one data node is offline. Three etcd voters with only two PostgreSQL nodes solve election quorum, not data-copy availability. Relaxed synchronous mode can deliberately permit single-node writes while disabling safe automatic failover until replication is restored; record the policy rather than silently weakening it.

For planned switchover: quiesce all k3s server writers, record source WAL position, wait until standby has replayed it, stop/fence the original primary, promote the standby, update/test writer routing, then restart servers against that endpoint. Never let both SQL copies accept kine writes. For failback, reseed or rewind the demoted node after timeline validation; never restart its stale primary data directory as a writer.

## Rehearsal and migration acceptance

1. Pin the running PostgreSQL major/image and create fresh verified SQL backup **plus roles/global settings** and protected server token/config. Avoid pulling mutable `postgres:latest` during Docker/OS maintenance; that could change database major/version and image data layout.
2. Build the selected topology outside production using a restored database and isolated k3s test cluster/token. Match actual k3s `v1.32.6+k3s1` behavior before a separate upgrade.
3. Exercise planned switchover, primary stop, network partition, lost witness/quorum, lost replica, restart of all hosts, and returning a stale former primary. Observe exactly one writer, routing, API reconnect, revision progression, and writes after recovery. Record acknowledged-write loss (target zero), outage time, and behavior under the selected replication policy.
4. Verify the HA endpoint and coordinator can boot with production Kubernetes stopped. Test a cold-start recovery, not only a running-cluster failover.
5. Adopt HA through reviewed non-Kubernetes IaC and protected credentials. Quiesce all k3s servers for final consistent transfer/adoption and endpoint change; preserve the existing server token and cluster CA/bootstrap state. A PostgreSQL restart is not a Kubernetes certificate rotation.
6. Update each server's root-owned datastore configuration, DB DNS/endpoint definition, backup jobs, and [asset catalogue](../asset-catalogue.md). Changes to Kubernetes applications still go through GitOps; agents do not issue ArgoCD write operations.
7. Test retiring physical k3s from epsilon without losing datastore/API reachability. Restore the pre-migration singleton only from a known consistent point with all competing writers fenced if rollback is needed; do not merge diverged kine histories.

## Decisions needed

Jack chooses manual-maintenance standby versus automatic HA, third-host placement, replication policy, and whether this executes before or after the Debian upgrade. The current live host state remains the singleton until implementation and acceptance.

References: [PostgreSQL 17 replication](https://www.postgresql.org/docs/17/warm-standby.html), [Patroni replication modes](https://patroni.readthedocs.io/en/latest/replication_modes.html), [Patroni fencing/watchdog](https://patroni.readthedocs.io/en/latest/watchdog.html), [pg_auto_failover architecture](https://pg-auto-failover.readthedocs.io/en/main/architecture.html), and [k3s datastore drivers/prepared statements](https://docs.k3s.io/datastore).
