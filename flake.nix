{
  description = "NixOS module for secure Tailscale SSH configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.tailscale-ssh;
        in
        {
          options.services.tailscale-ssh = {
            enable = lib.mkEnableOption "Enable secure Tailscale SSH configuration";

            interfaceName = lib.mkOption {
              type = lib.types.str;
              default = "tailscale0";
              description = "Name of the Tailscale interface";
            };

            sshPort = lib.mkOption {
              type = lib.types.port;
              default = 22;
              description = "SSH port to secure with Tailscale";
            };

            checkInterval = lib.mkOption {
              type = lib.types.int;
              default = 300;
              description = "Interval in seconds between Tailscale status checks";
            };
          };

          config = lib.mkIf cfg.enable {
            # Only set required tailscale settings
            services.tailscale = {
              enable = true;
              openFirewall = true;
              interfaceName = cfg.interfaceName;
            };

            # Basic firewall configuration
            networking.firewall = {
              enable = lib.mkDefault true;
              trustedInterfaces = [ cfg.interfaceName ];
              allowedTCPPorts = [ cfg.sshPort ];
            };

            # Required packages
            environment.systemPackages = with pkgs; [
              tailscale
              jq
              iproute2
              iptables
            ];

            # SSH Firewall management service
            systemd.services.tailscale-firewall = {
              description = "Manage SSH firewall rules based on Tailscale status";
              after = [
                "network.target"
                "tailscaled.service"
              ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [
                jq
                iproute2
                iptables
                tailscale
                gawk
              ];

              serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = "10s";
              };

              script = ''
                log() {
                  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
                }

                rule_exists() {
                  iptables -C $@ 2>/dev/null
                }

                apply_rule() {
                  local action=$1
                  shift
                  if ! rule_exists $@; then
                    if $action $@ 2>/dev/null; then
                      log "Applied: $action $@"
                    else
                      log "Failed to apply: $action $@ (Unexpected error)"
                    fi
                  else
                    if [[ "$action" == *"-A"* || "$action" == *"-I"* ]]; then
                      log "Rule already exists: $@"
                    elif [[ "$action" == *"-D"* ]]; then
                      if $action $@ 2>/dev/null; then
                        log "Removed existing rule: $@"
                      else
                        log "Failed to remove existing rule: $@ (Unexpected error)"
                      fi
                    fi
                  fi
                }

                get_default_interface() {
                  ip route | awk '/default/ {print $5; exit}'
                }

                update_firewall() {
                  local current_status=$1
                  local previous_status=$2
                  local default_interface=$(get_default_interface)

                  log "Checking Tailscale status. Current: $current_status, Previous: $previous_status"

                  if [ "$current_status" != "$previous_status" ]; then
                    if [ "$current_status" = "true" ]; then
                      log "Tailscale is up. Restricting SSH to Tailscale interface."
                      apply_rule "iptables -D INPUT" "-p tcp --dport ${toString cfg.sshPort} -j ACCEPT"
                      apply_rule "iptables -I INPUT" "-i ${cfg.interfaceName} -p tcp --dport ${toString cfg.sshPort} -j ACCEPT"
                      apply_rule "iptables -A INPUT" "-p tcp --dport ${toString cfg.sshPort} -j DROP"
                    else
                      log "Tailscale is down. Allowing SSH on all interfaces."
                      apply_rule "iptables -D INPUT" "-p tcp --dport ${toString cfg.sshPort} -j DROP"
                      apply_rule "iptables -D INPUT" "-i ${cfg.interfaceName} -p tcp --dport ${toString cfg.sshPort} -j ACCEPT"
                      apply_rule "iptables -I INPUT" "-p tcp --dport ${toString cfg.sshPort} -j ACCEPT"
                    fi
                    log "SSH rules updated. Default interface: ''${default_interface:-Not detected}, Tailscale interface: ${cfg.interfaceName}"
                  elif [ -z "$previous_status" ]; then
                    if [ "$current_status" = "true" ]; then
                      log "Initial state: Tailscale is up"
                    else
                      log "Initial state: Tailscale is down"
                    fi
                  else
                    log "No change in Tailscale status. No action taken."
                  fi
                }

                log "Starting Tailscale firewall management service"
                previous_status=""
                check_count=0

                while true; do
                  current_status=$(tailscale status --json | jq -r '.BackendState == "Running"')
                  update_firewall "$current_status" "$previous_status"
                  previous_status=$current_status
                  check_count=$((check_count + 1))
                  log "Completed check #$check_count. Sleeping for ${toString cfg.checkInterval} seconds."
                  sleep ${toString cfg.checkInterval}
                done
              '';
            };
          };
        };
    };
}
