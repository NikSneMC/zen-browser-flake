{
  description = "Zen Browser";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (builtins) split head tail isString concatStringsSep mapAttrs attrValues groupBy listToAttrs readFile fromJSON;

    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    inherit (pkgs) lib callPackage;
    inherit (lib) pipe mapAttrs' nameValuePair attrsToList flatten;

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
      system = head parts;
      suffix = pipe parts [
        tail
        (map (p:
          if isString p
          then p
          else ""))
        (concatStringsSep "-")
      ];
    };

    mkZen = system: suffix: key: ver: src: let
      version = "${key}${suffix}";

      sourceInfo = {
        inherit system src;
        version = "${ver}${suffix}";
      };

      unwrapped = callPackage ./package-unwrapped.nix {inherit sourceInfo;};
      wrapped = callPackage ./package.nix {inherit unwrapped;};
    in {
      "${version}-unwrapped" = unwrapped;
      ${version} = wrapped;
    };

    mkPackages = info:
      pipe (info.versions // (mapAttrs (_: version: info.versions.${version}) info.channels)) [
        (mapAttrs (version: meta:
          pipe meta.downloads [
            (mapAttrs' (sys: download: let
              sys_split = splitSys sys;
              system = sys_split.system;
              suffix = sys_split.suffix;
            in
              nameValuePair system (mkZen system suffix version meta.info.version download)))
            attrsToList
          ]))
        attrValues
        flatten
        (groupBy ({name, ...}: name))
        (mapAttrs (_: downloads: pipe downloads [(map ({value, ...}: value)) (map attrsToList) flatten listToAttrs]))
      ];
  in {
    packages = pipe ./info.json [
      readFile
      fromJSON
      mkPackages
    ];
  };
}
