{
  description = "NixOS module for secure Tailscale SSH configuration that automatically manages firewall rules based on Tailscale status";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.default = import ./module.nix;
    };
}
