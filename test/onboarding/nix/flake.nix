{
  description = "Mob onboarding test environment — Nix path (pins Elixir 1.18 / OTP 27)";

  inputs = {
    # Pin to a specific nixpkgs commit that provides elixir_1_18 + erlang_27.
    # Update this hash after verifying a newer commit still passes the tests.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          name = "mob-onboarding-nix";

          buildInputs = [
            pkgs.elixir_1_18   # 1.18.x built against OTP 27
            pkgs.erlang_27
            pkgs.git
            pkgs.gnumake
            pkgs.coreutils
            # Deliberately NOT including pkgs.curl — the onboarding tests must
            # not depend on Nix-managed curl because its CA bundle differs from
            # the macOS system bundle, causing GitHub Releases SSL failures.
            # mob's OtpDownloader uses :httpc (Erlang's HTTP client) which
            # inherits the system CA bundle via macOS Security framework.
          ];

          shellHook = ''
            # Put /usr/bin first so system curl, xcrun, and adb are always found
            # before any Nix-provided alternatives. This matches the environment
            # that the Nova user issue was diagnosed against.
            export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

            # Unset Nix's CA override so Erlang's :httpc uses the system bundle
            unset NIX_SSL_CERT_FILE
            unset SSL_CERT_FILE

            echo "Mob onboarding Nix shell — Elixir $(elixir --version | grep Elixir)"
          '';
        };
      }
    );
}
