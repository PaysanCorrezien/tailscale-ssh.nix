# 🔒 Tailscale SSH Security Module for NixOS

A NixOS module that provides automated, secure SSH access management through Tailscale, dynamically adjusting firewall rules based on Tailscale connection status.

## 📋 Overview

This module enhances SSH security by automatically restricting SSH access to the Tailscale interface when Tailscale is active, and falling back to standard SSH access when Tailscale is unavailable. It provides robust monitoring and automatic firewall rule management.

## ✨ Key Features

- 🔄 Dynamic firewall rule management based on Tailscale status
- 🛡️ Automatic failover to standard SSH when Tailscale is down
- 📊 Robust status monitoring with retry mechanism
- 🔍 Detailed logging for troubleshooting
- ⚙️ Configurable interface names, ports, and check intervals

## 🚀 Installation

1. Add the module to your `flake.nix`:

```nix
{
  inputs.tailscale-ssh.url = "github:paysancorrezien/tailscale-ssh.nix";


  outputs = { self, nixpkgs, tailscale-ssh }: {
    nixosConfigurations.yourHost = nixpkgs.lib.nixosSystem {
      modules = [
        tailscale-ssh.nixosModules.default
        # Your other modules...
      ];
    };
  };
}
```

2. Configure the service in your NixOS configuration:

```nix
{
  services.tailscale-ssh = {
    enable = true;
    # Optional: Customize these settings
    interfaceName = "tailscale0";
    sshPort = 22;
    checkInterval = 300;
  };
}
```

## ⚙️ Configuration Options

| Option          | Type    | Default        | Description                               |
| --------------- | ------- | -------------- | ----------------------------------------- |
| `enable`        | boolean | `false`        | Enable the Tailscale SSH security service |
| `interfaceName` | string  | `"tailscale0"` | Tailscale interface name                  |
| `sshPort`       | port    | `22`           | SSH port to secure                        |
| `checkInterval` | integer | `300`          | Status check interval in seconds          |

## 🔧 How It Works

The module:

1. Monitors Tailscale connection status
2. Automatically updates firewall rules based on status changes
3. Restricts SSH access to Tailscale interface when active
4. Provides fallback SSH access when Tailscale is down
5. Maintains detailed logs for monitoring

## 🤝 Contributing

Contributions are welcome! Please note:

- This project is maintained as time permits
- Focus on meaningful improvements that don't add unnecessary complexity

## 📄 License

This project follows the MIT License conventions. Feel free to use, modify, and distribute as per MIT License terms.

## 🔗 Related Projects

- [Tailscale](https://github.com/tailscale/tailscale)
- [NixOS](https://github.com/NixOS/nixpkgs)
