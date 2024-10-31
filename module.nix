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
    services.tailscale = {
      enable = true;
      openFirewall = lib.mkDefault false;
      interfaceName = cfg.interfaceName;
    };

    services.openssh.openFirewall = lib.mkDefault false;

    networking.firewall = {
      enable = lib.mkDefault true;
      trustedInterfaces = [ cfg.interfaceName ];
      allowedTCPPorts = [ cfg.sshPort ];
    };

    environment.systemPackages = with pkgs; [
      tailscale
      jq
      iproute2
      iptables
    ];

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
        # Added cleanup on service stop
        ExecStop = ''
          ${pkgs.iptables}/bin/iptables -D INPUT -p tcp --dport ${toString cfg.sshPort} -j DROP 2>/dev/null || true
          ${pkgs.iptables}/bin/iptables -D INPUT -i ${cfg.interfaceName} -p tcp --dport ${toString cfg.sshPort} -j ACCEPT 2>/dev/null || true
          ${pkgs.iptables}/bin/iptables -D INPUT -p tcp --dport ${toString cfg.sshPort} -j ACCEPT 2>/dev/null || true
        '';
      };

      script = ''
        # Use configuration variables
        TAILSCALE_INTERFACE="${cfg.interfaceName}"
        SSH_PORT=${toString cfg.sshPort}
        CHECK_INTERVAL=${toString cfg.checkInterval}

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

        # Improved Tailscale status checking with retries
        check_tailscale_status() {
          local attempts=3
          local delay=2
          local attempt=1
          
          while [ $attempt -le $attempts ]; do
            local status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState == "Running"' 2>/dev/null)
            if [ -n "$status" ]; then
              echo "$status"
              return 0
            fi
            log "Attempt $attempt/$attempts: Failed to get Tailscale status, retrying in $delay seconds..."
            sleep $delay
            attempt=$((attempt + 1))
          done
          
          log "WARNING: Failed to get reliable Tailscale status after $attempts attempts"
          echo "false"  # Default to down state if we can't get reliable status
          return 0
        }

        update_firewall() {
          local current_status=$1
          local previous_status=$2
          local default_interface=$(get_default_interface)

          log "Checking Tailscale status. Current: $current_status, Previous: $previous_status"

          if [ "$current_status" != "$previous_status" ]; then
            if [ "$current_status" = "true" ]; then
              log "Tailscale is up. Restricting SSH to Tailscale interface."
              apply_rule "iptables -D INPUT" "-p tcp --dport $SSH_PORT -j ACCEPT"
              apply_rule "iptables -I INPUT" "-i $TAILSCALE_INTERFACE -p tcp --dport $SSH_PORT -j ACCEPT"
              apply_rule "iptables -A INPUT" "-p tcp --dport $SSH_PORT -j DROP"
            else
              log "Tailscale is down. Allowing SSH on all interfaces."
              apply_rule "iptables -D INPUT" "-p tcp --dport $SSH_PORT -j DROP"
              apply_rule "iptables -D INPUT" "-i $TAILSCALE_INTERFACE -p tcp --dport $SSH_PORT -j ACCEPT"
              apply_rule "iptables -I INPUT" "-p tcp --dport $SSH_PORT -j ACCEPT"
            fi
            log "SSH rules updated. Default interface: ''${default_interface:-Not detected}, Tailscale interface: $TAILSCALE_INTERFACE"
          elif [ -z "$previous_status" ]; then
            if [ "$current_status" = "true" ]; then
              log "Initial state: Tailscale is up"
              # Apply initial rules for Tailscale up state
              apply_rule "iptables -I INPUT" "-i $TAILSCALE_INTERFACE -p tcp --dport $SSH_PORT -j ACCEPT"
              apply_rule "iptables -A INPUT" "-p tcp --dport $SSH_PORT -j DROP"
            else
              log "Initial state: Tailscale is down"
              # Apply initial rules for Tailscale down state
              apply_rule "iptables -I INPUT" "-p tcp --dport $SSH_PORT -j ACCEPT"
            fi
          else
            log "No change in Tailscale status. No action taken."
          fi
        }

        log "Starting Tailscale firewall management service"
        log "Configuration: Interface=$TAILSCALE_INTERFACE, SSH Port=$SSH_PORT, Check Interval=$CHECK_INTERVAL"
        previous_status=""
        check_count=0

        while true; do
          # Using the new robust status checking
          current_status=$(check_tailscale_status)
          update_firewall "$current_status" "$previous_status"
          previous_status=$current_status
          check_count=$((check_count + 1))
          log "Completed check #$check_count. Sleeping for $CHECK_INTERVAL seconds."
          sleep $CHECK_INTERVAL
        done
      '';
    };
  };
}
