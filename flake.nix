{
  description = "NixOS module for secure Tailscale SSH configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.default = import ./module.nix;
    };
}
