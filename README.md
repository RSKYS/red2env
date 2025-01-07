# Red2Env

### Todo:
- [ ] Finish Debian script (Proper partition detect)
- [x] init.nix for NixOS
- [ ] Finish NixOS scripts (Almost same issue)
- [ ] init.nix for Debian
- [ ] Finish Debian script (Almost same issue)
- [ ] Slackserv script
- [ ] All in one overwrite program
- [ ] Improvements for init.nix (let vars, merge init.nix, etc)

## NixOS
For NixOS install, we will use NixOS. although we still need to make it executable way more generally supported.
NixOS requirement should only become need for Nix.

Run the following command as root #:
```
curl https://raw.githubusercontent.com/RSKYS/red2env/master/nix/init.nix > init.nix; nix-shell init.nix --impure
```

## Debian
For Debian install, this is very minimal script compared to setup. note that it's still lacks the proper disk-name detection so if you're using NVMe, you need `nvme0nXpN` instead of `sdXN` for example, so adjust accordingly.
Use it on vm rescue/installer with partition structure of efi/swap/root in order.

Run the following command as root #:
```
curl https://raw.githubusercontent.com/RSKYS/red2env/master/deb/init.sh | bash
```
