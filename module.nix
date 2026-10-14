{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.services.vproxy;
  home = "/var/lib/vproxy";
  jsonFormat = pkgs.formats.json {};
  baseVersion = (pkgs.callPackage ./package.nix {}).version;
  inherit (lib) mkOption types;
  secretUnits = lib.optional (cfg.secretInstallService != null && cfg.secretInstallService != "") cfg.secretInstallService;
  injectPassword = cfg.adminPasswordFile != null;
in {
  options.services.vproxy = with lib.types; {
    enable = lib.options.mkEnableOption "vproxy";
    package = lib.mkOption {
      type = package;
      default = pkgs.callPackage ./package.nix {};
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The vertex proxy package to use.";
    };
    autoAgree = lib.mkOption {
      type = bool;
      default = false;
      description = ''
        Automatically agree to the rules of vertex proxy by writing the pre-calculated hash to the config/state/.rules_agreed file. Based on ${baseVersion}

        Making this option true implies you have read and agreed to the rules. If you don't agree, leave this option false and do not run vertex proxy.
      '';
    };
    currentHash = lib.mkOption {
      type = str;
      default = "36800adeec862126";
      internal = true;
      description = ''
        The pre-calculated hash of the rules of vertex proxy. Based on release tag ${baseVersion}
      '';
    };
    adminPasswordFile = lib.mkOption {
      type = nullOr externalPath;
      default = null;
      description = "Password file to admin panel";
    };
    secretInstallService = lib.mkOption {
      type = nullOr str;
      default = null;
      description = ''
        The service that installs the adminPasswordFile into its place. If you are using password managers like sops-nix or agenix or installing a out-of-store file as password.

        If you don't know what this is, leave this unspecified. If you are using an out-of-store password file, make this an empty string.
      '';
    };
    user = lib.mkOption {
      type = str;
      default = "vproxy";
      description = "User to run vertex proxy as.";
    };
    group = lib.mkOption {
      type = str;
      default = "vproxy";
      description = "Group to run vertex proxy as.";
    };
    # value from original repo, admin password left empty intentionally since content of the generated config goes into the Nix store, which any user on the machine can read
    # To actually specify a value to the admin_password config key, use `services.vproxy.adminPasswordFile` and `secretInstallService`.
    config = lib.mkOption {
      description = "Configuration written to vertex proxy's config.json.";
      default = {};
      type = types.submodule {
        freeformType = jsonFormat.type;
        options = {
          drop_max_tokens = mkOption {
            type = types.bool;
            default = false;
            description = "Remove `max_tokens` from upstream requests.";
          };

          aggregate_stream = mkOption {
            type = types.bool;
            default = false;
            description = "Combine streamed upstream chunks into one response.";
          };

          fake_stream_enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Simulate streaming for clients when the upstream response isn't streamed.";
          };

          default_image_size = mkOption {
            type = types.str;
            default = "1K";
            example = "2K";
            description = "Image size used when the request doesn't set one.";
          };

          default_response_modalities = mkOption {
            type = types.str;
            default = "图文";
            description = "Response modalities used when the request doesn't set them.";
          };

          max_n = mkOption {
            type = types.ints.positive;
            default = 8;
            description = "Maximum value accepted for `n` (number of generations) in one request.";
          };

          max_retries = mkOption {
            type = types.ints.unsigned;
            default = 1;
            description = "Number of retries for a failed upstream request.";
          };

          proxy_url = mkOption {
            type = types.str;
            default = "";
            example = "http://127.0.0.1:7890";
            description = "Proxy URL for upstream requests. Empty means no proxy.";
          };

          proxy_url_candidates = mkOption {
            type = types.listOf types.str;
            default = [];
            example = ["http://127.0.0.1:7890" "socks5://127.0.0.1:1080"];
            description = "Candidate proxy URLs to choose from.";
          };

          parallel_pool_enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Send requests to upstream nodes in parallel.";
          };

          parallel_pool_size = mkOption {
            type = types.ints.positive;
            default = 15;
            description = "Maximum number of concurrent requests in the parallel pool.";
          };

          parallel_pool_delay_ms = mkOption {
            type = types.ints.unsigned;
            default = 2500;
            description = "Delay in milliseconds between dispatches in the parallel pool.";
          };

          parallel_pool_delay_dynamic = mkOption {
            type = types.bool;
            default = false;
            description = "Adjust the parallel pool delay automatically instead of using a fixed value.";
          };

          entry_proxy_probe_enabled = mkOption {
            type = types.bool;
            default = false;
            description = "Check entry proxies' health at regular intervals.";
          };

          entry_proxy_probe_interval_seconds = mkOption {
            type = types.ints.positive;
            default = 300;
            description = "Seconds between entry proxy health checks.";
          };

          entry_proxy_probe_cooldown_seconds = mkOption {
            type = types.ints.unsigned;
            default = 60;
            description = "Cooldown in seconds after an entry proxy health check fails.";
          };

          entry_proxy_probe_auto_disable_enabled = mkOption {
            type = types.bool;
            default = false;
            description = "Disable an entry proxy automatically after repeated failed health checks.";
          };

          entry_proxy_probe_auto_disable_failures = mkOption {
            type = types.ints.positive;
            default = 10;
            description = "Consecutive failed health checks before an entry proxy is disabled.";
          };

          sticky_node_priority = mkOption {
            type = types.bool;
            default = false;
            description = "Keep using the last successful node before trying others.";
          };

          telemetry_enabled = mkOption {
            type = types.bool;
            default = false;
            description = "Turn on telemetry reporting.";
          };
        };
      };
    };
  };
  config = lib.mkIf cfg.enable {
    warnings = (
      if (cfg.package.version != baseVersion)
      then [
        "Package version changed (expecting ${baseVersion}, found ${cfg.package.version}), agreement might also updated. Please read the new agreement to see changes."
      ]
      else []
    );
    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        inherit (cfg) group;
      };
      groups.${cfg.group} = {};
    };
    systemd.tmpfiles.settings."10-vproxy" = let
      dir = {
        mode = "0750";
        inherit (cfg) user group;
      };
    in {
      ${home}.d = dir;
      "${home}/config".d = dir;
      "${home}/config/state".d = dir // {mode = "0700";};
      "${home}/logs".d = dir;
      "${home}/config/config.json".f = {
        mode = "0660";
        inherit (cfg) user group;
        argument = builtins.toJSON cfg.config;
      };
    };
    systemd.services."vproxy-agree-agreement" = lib.mkIf cfg.autoAgree {
      description = "Auto agree to the rules of vertex proxy by writing the pre-calculated hash to the config/state/.rules_agreed file";

      requires = ["systemd-tmpfiles-setup.service"];
      after = ["systemd-tmpfiles-setup.service"];
      script = ''
        set -euo pipefail
        printf "%s\t%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${cfg.currentHash}" > ${home}/config/state/.rules_agreed
      '';
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0077";
      };
    };

    systemd.services."vproxy-inject-password" = let
      json_key = "admin_password";
    in
      lib.mkIf injectPassword {
        description = "Substitute admin password into the config file";

        requires = ["systemd-tmpfiles-setup.service"];
        after = ["systemd-tmpfiles-setup.service"] ++ secretUnits;
        path = [pkgs.jq];
        script = ''
          set -euo pipefail

          config_file="${home}/config/config.json"
          secret_file=${cfg.adminPasswordFile}

          jq -e 'type == "object"' "$config_file" > /dev/null

          if jq -e 'has("${json_key}")' "$config_file" > /dev/null; then
            exit 0
          fi

          tmp=$(mktemp -- "$config_file.XXXXXX")
          trap 'rm -f -- "$tmp"' EXIT

          jq --rawfile apiKey "$secret_file" \
            '. + {${json_key}: ($apiKey | rtrimstr("\n"))}' \
            "$config_file" > "$tmp"

          chown --reference="$config_file" "$tmp"
          chmod --reference="$config_file" "$tmp"

          mv -f -- "$tmp" "$config_file"
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          UMask = "0077";
        };
      };
    # Not started on boot or rebuild: the app writes its own fields into config.json,
    # so resetting it to the Nix settings is opt-in via `systemctl start vproxy-apply-config`.
    # The app hot-reloads config.json, so no restart is needed.
    systemd.services."vproxy-apply-config" = {
      description = "Overwrite the vertex proxy config file with Nix-declared settings";

      requires = ["systemd-tmpfiles-setup.service"];
      after = ["systemd-tmpfiles-setup.service"];
      # re-populate admin_password after the overwrite
      wants = lib.optional injectPassword "vproxy-inject-password.service";
      before = lib.optional injectPassword "vproxy-inject-password.service";
      script = ''
        set -euo pipefail

        config_file="${home}/config/config.json"

        tmp=$(mktemp -- "$config_file.XXXXXX")
        trap 'rm -f -- "$tmp"' EXIT

        install -m 0660 -o ${cfg.user} -g ${cfg.group} ${jsonFormat.generate "vproxy-config.json" cfg.config} "$tmp"

        mv -f -- "$tmp" "$config_file"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
      };
    };

    systemd.services.vertex-proxy = let
      deps =
        lib.optional injectPassword "vproxy-inject-password.service"
        ++ lib.optional cfg.autoAgree "vproxy-agree-agreement.service";
    in {
      description = "Vertex AI proxy";
      requires = deps;
      after = deps ++ ["network.target"];
      wantedBy = ["multi-user.target"];
      environment.VPROXY_CONFIG = "${home}/config/config.json";
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        # upstream resolves config/state/.rules_agreed relative to the working directory
        WorkingDirectory = home;
        ExecStart = "${cfg.package}/bin/vertex-proxy";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
