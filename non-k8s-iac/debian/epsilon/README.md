# Epsilon Debian runtime constraints

[`runtime.pref`](runtime.pref) is deployed at `/etc/apt/preferences.d/epsilon-runtime` during Jack's approved physical maintenance window. It selects the exact Docker/containerd/Compose/Buildx versions accepted in the [isolated Bookworm/Trixie rehearsal](../../../docs/plans/epsilon-debian-upgrade.md#debian-13-clone-rehearsal-accepted-october-8).

The repository offered containerd2.4.1 after rehearsal; Jack selected the rehearsed2.3.6 runtime for physical execution. This preference persists across the Debian suite change and blocks automatic selection of unrehearsed newer runtime versions. It is not an apt-mark hold. Review/update these constraints with runtime maintenance and accepted compatibility tests; don't silently leave them out of recovery or package planning.

Debian sources/security drivers remain independently updated. The physical Bookworm security components include contrib/non-free/non-free-firmware to resolve the observed NVIDIA driver/firmware mismatch. The original source/configuration and fresh datastore/service recovery artifacts are preserved outside Git; see the [physical maintenance checkpoint](../../../docs/plans/epsilon-debian-upgrade.md#privileged-preparation-and-accepted-runtime-constraint).
