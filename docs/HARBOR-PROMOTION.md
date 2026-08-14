# Harbor consumption

The release workflow publishes immutable tags to GHCR. Homelab consumes the accepted image through the authenticated Harbor Proxy Cache project `private-ghcr`.

Canonical runtime path:

```text
harbor.lab.skunklabs.uk/private-ghcr/ignazio-ingenito/developer-workspace:<immutable-calver>
```

There is no steady-state manual `skopeo copy`, hosted-project promotion, or preventive GHCR → Harbor replication step. On cache miss, Harbor resolves the immutable upstream artifact from GHCR and then owns registry scanning/rescanning.

Operational flow:

1. verify the producer CI built, tested and scanned the exact artifact that was published;
2. select the immutable CalVer accepted for deployment;
3. update `homelab` to the canonical Harbor Proxy Cache reference;
4. let Harbor fetch the GHCR artifact on cache miss;
5. verify the running image identity and keep the previous known-good CalVer/digest for rollback.

Credentials remain owned by the producer/GHCR publication path and by Homelab's Harbor pull configuration. Do not add Harbor push credentials to this repository.
