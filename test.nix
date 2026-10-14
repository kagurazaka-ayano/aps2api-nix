{self}: {
  name = "vproxy";

  nodes.machine = {pkgs, ...}: {
    imports = [self.nixosModules.default];

    # Stand-in for sops-nix / agenix: installs the admin password outside the store.
    systemd.services.install-vproxy-secret = {
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 /run/secrets
        printf 'hunter2\n' > /run/secrets/vproxy-admin
        chmod 0400 /run/secrets/vproxy-admin
      '';
    };

    services.vproxy = {
      enable = true;
      autoAgree = true;
      adminPasswordFile = "/run/secrets/vproxy-admin";
      secretInstallService = "install-vproxy-secret.service";
      config = {
        max_retries = 3;
        # freeform key, not declared as an option
        port_api = 8080;
      };
    };

    environment.systemPackages = [pkgs.curl pkgs.jq];
  };

  testScript = ''
    import json

    machine.wait_for_unit("vertex-proxy.service")
    machine.wait_for_open_port(8080)

    with subtest("rules agreement is written"):
        machine.succeed("grep -q 36800adeec862126 /var/lib/vproxy/config/state/.rules_agreed")

    with subtest("config.json contains settings and injected password"):
        cfg = json.loads(machine.succeed("cat /var/lib/vproxy/config/config.json"))
        assert cfg["max_retries"] == 3, cfg
        assert cfg["port_api"] == 8080, cfg
        assert cfg["telemetry_enabled"] is False, cfg
        assert cfg["admin_password"] == "hunter2", cfg
        machine.succeed("test \"$(stat -c %U /var/lib/vproxy/config/config.json)\" = vproxy")

    with subtest("service runs unprivileged"):
        machine.succeed("test \"$(systemctl show -p User --value vertex-proxy.service)\" = vproxy")

    with subtest("health endpoint"):
        machine.succeed("curl -sf http://127.0.0.1:8080/health | jq -e '.status == \"healthy\"'")

    with subtest("admin login uses injected password"):
        machine.succeed(
            "curl -sf -X POST -H 'Content-Type: application/json' "
            "-d '{\"password\":\"hunter2\"}' http://127.0.0.1:8080/api/admin/login"
        )
        machine.fail(
            "curl -sf -X POST -H 'Content-Type: application/json' "
            "-d '{\"password\":\"wrong\"}' http://127.0.0.1:8080/api/admin/login"
        )

    with subtest("apply-config does not run on boot"):
        machine.succeed("test \"$(systemctl show -p ExecMainStartTimestampMonotonic --value vproxy-apply-config.service)\" = 0")

    with subtest("apply-config overwrites config and re-populates password"):
        machine.succeed(
            "jq '.max_retries = 1 | .admin_password = \"changed\" | .app_written = true' "
            "/var/lib/vproxy/config/config.json > /tmp/c.json && cat /tmp/c.json > /var/lib/vproxy/config/config.json"
        )
        machine.succeed("systemctl start vproxy-apply-config.service")
        cfg = json.loads(machine.succeed("cat /var/lib/vproxy/config/config.json"))
        assert cfg["max_retries"] == 3, cfg
        assert "app_written" not in cfg, cfg
        assert cfg["admin_password"] == "hunter2", cfg
        machine.succeed("test \"$(stat -c %U:%G:%a /var/lib/vproxy/config/config.json)\" = vproxy:vproxy:660")
        machine.succeed("systemctl is-active vertex-proxy.service")

    with subtest("reload keeps the service running"):
        machine.succeed("systemctl reload vertex-proxy.service")
        machine.wait_for_open_port(8080)
        machine.succeed("systemctl is-active vertex-proxy.service")
  '';
}
