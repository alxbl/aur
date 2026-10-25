# alxbl/aur

Personal PKGBUILD repository for binary tools that have no official or AUR package. Each directory is one package; nothing is pre-built.

## Usage

Add to `/etc/paru.conf` or `~/.config/paru/paru.conf`:

```ini
[alxbl]
Url = https://github.com/alxbl/aur
```

Then:

```sh
paru -Sl alxbl            # list packages
paru -S alxbl/<package>   # build and install
```

Paru reads custom `[name]` sections as PKGBUILD repositories, so this works alongside the AUR without a separate server.

## Layout

```
<pkgname>/PKGBUILD   # one directory per package
<pkgname>/.SRCINFO   # generated, committed
templates/PKGBUILD-bin
```

## Conventions

- Name packages that repackage upstream release binaries with a `-bin` suffix.
- Pin `sha256sums`. Never use `SKIP`.
- Regenerate `.SRCINFO` after every PKGBUILD change: `makepkg --printsrcinfo > .SRCINFO`.
- Start a new package from `templates/PKGBUILD-bin`.
