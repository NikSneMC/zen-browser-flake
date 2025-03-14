{
  description = "Zen Browser";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (builtins) split;
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    inherit (pkgs) lib;
    inherit (lib) pipe;

    systems = {
      linux-aarch64 = "aarch64-linux";
      linux-x86_64 = "x86_64-linux";
      linux-generic = "x86_64-linux.generic";
      linux-specific = "x86_64-linux.specific";
      linux = "x86_64-linux";
    };

    splitSys = sys: let
      parts = pipe sys [
        (name: systems.${name})
        (split "\\.")
      ];
    in {
      system = builtins.head parts;
      suffix = pipe parts [
        builtins.tail
        (map (p:
          if builtins.isString p
          then p
          else ""))
        (builtins.concatStringsSep "-")
      ];
    };

    mkZen = system: suffix: key: ver: src: let
      version = "${key}${suffix}";

      sourceInfo = {
        inherit system src;
        version = "${ver}${suffix}";
      };

      unwrapped = pkgs.callPackage ./package-unwrapped.nix {inherit sourceInfo;};
      wrapped = pkgs.callPackage ./package.nix {inherit unwrapped;};
    in {
      "${version}-unwrapped" = unwrapped;
      ${version} = wrapped;
    };

    mkPackages = info: let
      inherit (builtins) mapAttrs;
      inherit (lib) attrsToList flatten;
    in
      pipe (info.versions // (mapAttrs (_: version: info.versions.${version}) info.channels)) [
        (mapAttrs (version: meta:
          pipe meta.downloads [
            (lib.mapAttrs' (sys: download: let
              sys_split = splitSys sys;
              system = sys_split.system;
              suffix = sys_split.suffix;
            in
              lib.nameValuePair system (mkZen system suffix version meta.info.version download)))
            attrsToList
          ]))
        builtins.attrValues
        lib.flatten
        (builtins.groupBy (download: download.name))
        (mapAttrs (_: downloads: pipe downloads [(map (download: download.value)) (map attrsToList) flatten builtins.listToAttrs]))
      ];
  in {
    packages = pipe ./info.json [
      builtins.readFile
      builtins.fromJSON
      mkPackages
    ];
  };
}
