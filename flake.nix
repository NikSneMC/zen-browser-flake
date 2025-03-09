{
  description = "Zen Browser";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    inherit (builtins) split elemAt attrValues;
    systems = {
      linux-aarch64 = "aarch64-linux";
      linux-x86_64 = "x86_64-linux";
      linux-generic = "x86_64-linux.generic";
      linux-specific = "x86_64-linux.specific";
      linux = "x86_64-linux";
    };
  in
    flake-utils.lib.eachSystem (map (s: builtins.head (split "\\." s)) (attrValues systems)) (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      inherit (lib) pipe;

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
      allPackages = pipe ./info.json [
        builtins.readFile
        builtins.fromJSON
        mkPackages
      ];
    in {
      packages = allPackages.${system};
    });
}
