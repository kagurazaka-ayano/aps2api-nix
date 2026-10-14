# aps2api-nix

A Nix flake that packages [APS2api](https://github.com/DeconstructedCube/APS2api) (`vertex-proxy`, an "Agent Platform Studio to API" proxy for Vertex AI) and ships a NixOS module to run it as a hardened systemd service.

- Package: APS2api **11b1f3b**, built from `cmd/vproxy`, installed as `bin/vertex-proxy`
- Platforms: `x86_64-linux`, `aarch64-linux`
- License of the packaged software: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/). Commercial use is not permitted.

## Flake outputs

| Output                                       | Description                                                                          |
| -------------------------------------------- | ------------------------------------------------------------------------------------ |
| `packages.<system>.default` / `vertex-proxy` | The `vertex-proxy` binary                                                            |
| `packages.<system>.docs`                     | Generated option documentation (`options.md`, `options.json`); also builds on Darwin |
| `nixosModules.default`                       | The `services.vproxy` NixOS module                                                   |
| `checks.<system>.vproxy`                     | NixOS VM test for the module                                                         |

## Usage

Add the flake to your system configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    aps2api.url = "github:kagurazaka-ayano/aps2api-nix";
    aps2api.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, aps2api, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        aps2api.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

Then enable the service:

```nix
{
  services.vproxy = {
    enable = true;

    # Only set this after reading the upstream rules (see "Rules agreement" below).
    autoAgree = true;

    # Admin panel password, kept out of the Nix store.
    adminPasswordFile = config.sops.secrets.vproxy-admin.path;
    secretInstallService = "sops-nix.service";

    config = {
      max_retries = 3;
      proxy_url = "http://127.0.0.1:7890";
      # Keys that are not declared as options are passed through to config.json as-is.
      port_api = 8080;
    };
  };
}
```

The full option reference is in [OPTIONS.md](OPTIONS.md).

## How it works

### Files and services

All state lives in `/var/lib/vproxy`, owned by `services.vproxy.user` / `group` (default `vproxy`):

```
/var/lib/vproxy/
├── config/
│   ├── config.json          # generated from services.vproxy.config
│   └── state/.rules_agreed  # written by autoAgree
└── logs/
```

| Unit                             | Runs                                            | Purpose                                                                                             |
| -------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `vertex-proxy.service`           | at boot                                         | The proxy itself. It runs as the unprivileged user, and its working directory is `/var/lib/vproxy`. |
| `vproxy-agree-agreement.service` | before the proxy, if `autoAgree`                | Writes the rules hash to `config/state/.rules_agreed`.                                              |
| `vproxy-inject-password.service` | before the proxy, if `adminPasswordFile` is set | Adds `admin_password` to `config.json` from the secret file.                                        |
| `vproxy-apply-config.service`    | **manually only**                               | Resets `config.json` to the Nix-declared settings.                                                  |

### Configuration lifecycle

`config.json` is created from `services.vproxy.config` **only if it does not exist yet**. vertex-proxy writes its own fields into this file at runtime, for example through the admin panel. To protect those changes, a rebuild does not overwrite an existing file.

To overwrite the file with your Nix settings after changing `services.vproxy.config`, run:

```sh
systemctl start vproxy-apply-config
```

This replaces `config.json` and then re-injects the admin password. vertex-proxy hot-reloads `config.json`, so you don't need to restart it. You can also send `SIGHUP` with `systemctl reload vertex-proxy`.

### Admin password

Anything in `services.vproxy.config` ends up in the world-readable Nix store, so do not put `admin_password` there. Instead:

- Set `adminPasswordFile` to the path of a file outside the store. A trailing newline is stripped.
- Set `secretInstallService` to the systemd unit that puts that file in place, such as `sops-nix.service` or `agenix.service`, so the injection waits for it. Leave it as `null` if you don't use a secret manager. Use `""` if the file is already present at boot.

The password is injected only if `config.json` does not already contain an `admin_password` key. A password changed not using this method is therefore kept until you run `vproxy-apply-config`.

### Rules agreement

On first start, upstream vertex-proxy requires you to accept its [rules](https://raw.githubusercontent.com/DeconstructedCube/APS2api/11b1f3b/cmd/vproxy/rules.txt) interactively. It stores the acceptance in `config/state/.rules_agreed` as a hash of the rules text. **Setting `autoAgree = true` means you have read and agreed to those rules.**

The hash is pre-computed for 11b1f3b. `calcHash.go` reproduces it. Runs it to recalculate hash:

```sh
go run calcHash.go <fileUrl>
```

If the package version ever differs from the version of the package in this repo, the module shows a warning because the rules may have changed. Read the new rules, update the URL in `calcHash.go`, and update `currentHash`.

## Development

```sh
# Build the package
nix build .#vertex-proxy

# Run the NixOS VM test (Linux, or a Linux remote builder)
nix flake check            # or: nix build .#checks.x86_64-linux.vproxy

# Regenerate OPTIONS.md after changing option declarations in module.nix
nix build .#docs && install -m 0644 result/options.md OPTIONS.md
```

The option documentation is generated by nixpkgs' [`nixosOptionsDoc`](https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/make-options-doc/default.nix) from the option declarations in `module.nix` (see `docs.nix`), the same tool that produces the NixOS manual's option reference.
