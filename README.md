# six-demo (38c3 talk)

![gplv3](https://www.gnu.org/graphics/gplv3-127x51.png)

[talk](https://media.ccc.de/v/38c3-sixos-a-nix-os-without-systemd), [slides](https://cfp.cccv.de/media/38c3-community-stages/submissions/8QZKGS/resources/sixos-talk_AeFJi9n.pdf)

This repo is Western Semiconductor's production cluster expressions as of
2024-Dez-28, with internal network maps hastily ripped out.  Things are a bit
messy, but the demo vm works, which gives you enough to answer questions like
"how does amjoseph do xyz".

To run the demo:

```
git clone https://codeberg.org/amjoseph/six
nix run --impure -f six host.demo.configuration.vm
```

Because almost everything in nixpkgs depends on `systemd`, and sixos doesn't use
`systemd`, you'll get almost no hits from the `hydra.nixos.org` cache.  So, be
prepared for a lot of compilation.

Everything in this repository is licensed under the GNU GPL version 3 (only);
see `COPYING.GPL3-ONLY`.
