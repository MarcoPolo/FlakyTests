{
  description = "A very basic flake";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-21.11";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { system = system; };
      in
      {
        packages.julia = import ./julia.nix {
          inherit pkgs system;
        };

        packages.startPluto = pkgs.writeScriptBin "startPluto" ''
          #!/bin/sh
          ${self.packages.${system}.julia}/bin/julia --project=. --optimize=0 -e "import Pluto; Pluto.run()"
        '';
        packages.init = pkgs.writeScriptBin "startPluto" ''
          #!/bin/sh
          ${self.packages.${system}.julia}/bin/julia --project=. --optimize=0 -e 'import Pkg; Pkg.instantiate();'
        '';
        packages.buildNotebook = pkgs.writeScriptBin "buildNotebook" ''
          #!/bin/sh
          ${self.packages.${system}.julia}/bin/julia --project=. --optimize=0 -e 'import Pkg; Pkg.instantiate(); import PlutoSliderServer; PlutoSliderServer.export_notebook("./notebook.jl")'
        '';
        defaultPackage = self.packages.${system}.startPluto;
        devShell = pkgs.mkShell {
          buildInputs = [ self.packages.${system}.julia self.packages.${system}.startPluto ];
        };
      });
}
