# alxbl/aur

Personal PKGBUILD repository for binary tools that have no official or AUR package. Each directory is one package; nothing is pre-built.

## Usage

Add to `/etc/paru.conf` or `~/.config/paru/paru.conf`:

```ini
[alxbl]
Url = https://github.com/alxbl/aur
```

Paru reads custom `[name]` sections as PKGBUILD repositories, so this works alongside the AUR without a separate server.

### Sync

Paru does not fetch a `Url` repository on its own. Until it has been downloaded, `paru -Sl alxbl` reports `repo alxbl not downloaded`. Download it, and refresh it to pick up new versions, with:

```sh
paru -Sy --pkgbuilds
```

Then:

```sh
paru -Sl alxbl            # list packages
paru -S alxbl/<package>   # build and install
```

Note that `-y` may also refresh the pacman sync databases. Installing after a database refresh without a full upgrade (`-u`) risks a partial upgrade, so prefer `paru -Syu`.

## Layout

```
<pkgname>/PKGBUILD   # one directory per package
<pkgname>/.SRCINFO   # generated, committed
templates/PKGBUILD-bin
update/<pkgname>.sh  # one updater per package
update/check-all.sh  # runs every updater
update/lib.sh        # helpers shared by the updaters
update/test.sh       # offline tests for the above
```

## Keeping packages current

```sh
update/check-all.sh -n    # report out-of-date packages, change nothing
update/check-all.sh       # bump what can be bumped
update/check-all.sh <pkgname>...   # only the named packages
```

Each updater looks up the latest upstream version. If it is newer, the updater bumps `pkgver`, resets `pkgrel`, rewrites the checksums and regenerates `.SRCINFO`. When it cannot do all of that, for example because upstream publishes no checksum, it changes nothing and only reports the package as out of date. A bump still needs review and a commit.

`check-all.sh` exits 1 on an error or a package without an updater, 2 if packages are out of date and not bumped, and 0 otherwise.

### Adding a package

Every package needs a matching `update/<pkgname>.sh`, and `check-all.sh` fails until it exists. Copy `update/istioctl-bin.sh`, then define:

- `latest_version`: print the newest upstream version in `pkgver` form.
- `checksums VERSION`: print `<checksum-array> <sha256>` for each array to rewrite, or return non-zero if a hash is unavailable.

Only single-element checksum arrays are rewritten. A change that needs more, such as new dependencies, belongs in a manual update; the updater should then only flag it.

Run `update/test.sh` after changing `lib.sh` or `check-all.sh`.

## Conventions

- Name packages that repackage upstream release binaries with a `-bin` suffix.
- Pin `sha256sums`. Never use `SKIP`.
- Regenerate `.SRCINFO` after every PKGBUILD change: `makepkg --printsrcinfo > .SRCINFO`.
- Start a new package from `templates/PKGBUILD-bin`, and add its updater.
