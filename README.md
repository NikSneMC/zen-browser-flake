# Zen Browser

This is a flake for the Zen browser.

Just add it to your NixOS `flake.nix` or home-manager:

```nix
inputs = {
  zen-browser = {
      url = "github:NikSneMC/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
  };
  ...
}
```

## Packages

This flake exposes three channels, alpha, beta and twilight, each with two packages, corresponding to the `specific` and `generic` zen versions.
The generic version maximizes compatibility with old CPUs and kernels by compiling it with some
lower common denominator CFLAGS, the `specific` one targets newer CPUs and kernels but it may not
work in your case.

Then in the `configuration.nix` in the `environment.systemPackages` add one of:

```nix
inputs.zen-browser.packages."${system}".alpha.specific
inputs.zen-browser.packages."${system}".alpha.generic
inputs.zen-browser.packages."${system}".beta.specific
inputs.zen-browser.packages."${system}".beta.generic
inputs.zen-browser.packages."${system}".twilight.specific
inputs.zen-browser.packages."${system}".twilight.generic
```

Depending on which version you want

```shell
$ sudo nixos-rebuild switch
$ zen
```

## 1Password

Zen has to be manually added to the list of browsers that 1Password will communicate with. See [this wiki article](https://nixos.wiki/wiki/1Password) for more information. To enable 1Password integration, you need to add the line `.zen-wrapped` to the file `/etc/1password/custom_allowed_browsers`.
