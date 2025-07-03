This repo stores the configuration used to define my homelab.

# History

Since 2023, I'd been self-hosting a Gitea instance that was used as the source both for configuration, and (for applications I wrote myself) for source code. In July 2025, a hard-drive failure prompted me to rebuild the cluster from the ground up, and I re-evaluated that choice.

Although I still conceptually agree with the reasons that led me to self-host a Git forge (centralization of development services, especially when owned by BigTech, leads to stagnation and exploitation), in practice my Gitea instance:
* was the most fragile/error-prone applications on the homelab - I've lost count of the number of times I had to simply tear it down and reinstall from scratch, resubmitting Git repos from local backups
* as such, was the biggest impediment to development on other interesting topics - if you can't work with source code, you can't really get _anything_ done.
* wasn't really doing a good job of _teaching_ me anything; and, in some cases, was actively holding me back from working on practices useful in other areas (like using GitHub's OIDC with Vault - at the time of writing, my PR to add that feature to Gitea is still languishing)

So - with some regret and shame - I've decided it's prudent to conform and use the industry standard; _[So I packed all my pamphlets with my bibles at the back of the shelf](https://frank-turner.com/tracks/love-ire-song/)_.
