# Documentation

## Operational documentation

These documents describe infrastructure and operational procedures. Keep them current as deployed assets and their recovery dependencies change.

- [Asset catalogue](asset-catalogue.md): physical/virtual assets, access paths, credentials, and recovery dependencies.
- [Cluster prerequisites](PREREQUISITES.md).
- [k3s PostgreSQL datastore and recovery](k3s-ha-postgres/README.md).
- [CloudNative-PG](cloudnative-pg.md).
- [external-dns setup](external-dns-setup.md).
- [Media quality profiles](media-quality-profiles.md).

## Plans and drafts

- [Active plans](plans/README.md): proposed work and execution-time acceptance criteria.
- [k3s outage recovery handoff](plans/k3s-outage-recovery-handoff.md): backup/restore, filesystem integrity and workflow acceptance after service restoration; coordinates with epsilon imaging.
- [Delivered plans](plans/delivered/README.md): archive of completed infrastructure plans.
- [Existing TODO proposals](todo/): detailed proposals for future work.
- [Blog drafts](blog-drafts/): unpublished writing, with deployment status identified in each draft.
- [external-dns blog notes](blog-post-notes-external-dns-opnsense.md).

Plans document intended state; the asset catalogue documents deployed state. When a plan is delivered, update operational documentation and versioned configuration, then archive the plan with its delivery date and outcome. Writing or merging a plan does not count as delivering its infrastructure changes.
