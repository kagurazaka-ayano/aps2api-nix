{
  description = "APS2api nixos module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    linuxSystems = ["aarch64-linux" "x86_64-linux"];
    allSystems = linuxSystems ++ ["aarch64-darwin"];
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages =
      nixpkgs.lib.recursiveUpdate (forSystems allSystems (pkgs: rec {
        default = pkgs.callPackage ./package.nix {};
        vertex-proxy = default;
      })) (forSystems allSystems (pkgs: {
        docs = import ./docs.nix {inherit pkgs;};
      }));
    nixosModules = {
      default = import ./module.nix;
    };
    checks = forSystems linuxSystems (pkgs: {
      vproxy = pkgs.testers.runNixOSTest (import ./test.nix {inherit self;});
    });
  };
}
