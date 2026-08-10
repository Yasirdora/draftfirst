# Releasing `@draftfirst/core`

This document is for package maintainers. Ordinary contributors do not need npm
publication access.

## Release requirements

Before changing a version or creating a GitHub release:

1. Start from an up-to-date, clean `main` branch.
2. Update `packages/draftfirst/CHANGELOG.md`.
3. Set the same release version in the root and package manifests.
4. Run `npm ci` followed by `npm run quality`.
5. Review the output of `npm pack --workspace=@draftfirst/core --dry-run`.

Published versions are immutable. Do not reuse a version number, even when a
release is immediately deprecated.

## First publication only

npm requires a package to exist before its Trusted Publisher can be configured.
The initial public version must therefore be bootstrapped by a maintainer who has
publish permission in the `draftfirst` npm organization:

```sh
npm login
npm whoami
npm publish --workspace=@draftfirst/core --access public
```

Complete npm's interactive two-factor authentication when prompted. Do not add
an npm access token to this repository or commit a user-level `.npmrc` file.

After the initial version exists, open the package settings on npm and configure
the GitHub Actions Trusted Publisher with these exact values:

- organization or user: `Yasirdora`
- repository: `draftfirst`
- workflow filename: `publish.yml`
- environment: `npm`
- allowed action: `npm publish`

Create the matching protected `npm` environment in the GitHub repository. Once
one automated release succeeds, restrict token-based publishing in npm and
revoke any temporary publication credentials.

## Subsequent releases

The `.github/workflows/publish.yml` workflow publishes from a GitHub Release by
using npm Trusted Publishing. It has no long-lived npm token and npm generates
provenance automatically.

1. Merge the reviewed release changes into `main`.
2. Create an annotated tag matching the package version, such as `v0.2.0`.
3. Create and publish the GitHub Release from that tag.
4. Confirm that CI passes and the npm publish workflow completes.
5. Verify the version, provenance, files, and public entry points on npm.

The workflow rejects a release whose tag does not exactly match the package
version.
