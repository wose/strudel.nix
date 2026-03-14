{
  description = "A strudel.cc application wrapper.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    strudel = {
      url = "https://codeberg.org/uzu/strudel";
      type = "git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      strudel,
    }:
    let
      supported_systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      for_all_systems =
        output:
        nixpkgs.lib.genAttrs supported_systems (
          system:
          output {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );
    in
    {
      inherit self;

      packages = for_all_systems (
        { pkgs, ... }:
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            name = "strudel.nix";
            src = strudel;

            nativeBuildInputs = with pkgs; [
              nodejs
              pnpmConfigHook
              pnpm
            ];

            pnpmDeps = pkgs.fetchPnpmDeps {
              pname = "strudel_pnpm_deps";
              src = strudel;
              fetcherVersion = 3;
              hash = "sha256-p3bLPpCz4Wnbsnj6PAcl/ByScjUhqyeXJwMSffs/kyA=";
            };

            buildPhase = "pnpm run build";

            installPhase =
              let
                targets = "{node_modules,website,packages,tools,examples}";
              in
              ''
                mkdir $out
                cp --recursive ${targets} $out

                # Disable the 'prestart' script, since it launches 'jsdoc', which
                # requires mutable runtime access but is implied in 'build' anyway.
                # Replace the 'start' script with 'preview'.
                # 'start' launches 'astro dev' which also requires mutable access.
                ${pkgs.jq}/bin/jq '
                  .scripts.prestart = "" |
                  .scripts.start = "pnpm preview"
                ' package.json > $out/package.json
              '';
          };
        }
      );

      apps = for_all_systems (
        { system, pkgs }:
        {
          default =
            let
              strudel_pkg = self.outputs.packages.${system}.default;
              strudel_wrapper = pkgs.writeShellApplication {
                name = "strudel_wrapper";
                #runtimeInputs = strudel_pkg.nativeBuildInputs;
                # I dont understand why i have to duplicate the inputs here
                # even though the nativeBuildInputs list is identical, execution
                # fails with a 'npm: command not found'. Building relies on and
                # works with npm too.
                runtimeInputs = with pkgs; [
                  nodejs
                  pnpmConfigHook
                  pnpm
                ];
                text = ''
                  export ASTRO_TELEMETRY_DISABLED=1
                  pushd ${strudel_pkg}
                  pnpm run start -- --open
                '';
              };
            in
            {
              meta.description = "Launches a server and opens strudel.cc in your browser.";
              type = "app";
              program = "${strudel_wrapper}/bin/strudel_wrapper";
            };
        }
      );

      devShells = for_all_systems (
        { system, pkgs }:
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.outputs.packages.${system}.default ];
          };
        }
      );

      formatter = for_all_systems ({ pkgs, ... }: pkgs.nixfmt);
    };
}
