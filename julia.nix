{ pkgs, system }:
let
  version = "1.8.2";
  shortVersion = "1.8";
  sha256 = builtins.getAttr system {
    # Use nix-prefetch-url https://julialang-s3.julialang.org/bin/linux/x64/1.8/julia-1.8.2-linux-x86_64.tar.gz
    "aarch64-darwin" = "19csaidzkcxbpbms75y8vwfz4lxwxxkzhm5iaf8m2ksi9vgd7wh6";
    "x86_64-linux" = "15p70ly9mw9896snq51fbc0nz1g3hy8gdmzd3rz72fmna2jg6737";
  };
  url = builtins.getAttr system {
    "aarch64-darwin" = "https://julialang-s3.julialang.org/bin/mac/aarch64/${shortVersion}/julia-${version}-macaarch64.dmg";
    "x86_64-linux" = "https://julialang-s3.julialang.org/bin/linux/x64/${shortVersion}/julia-${version}-linux-x86_64.tar.gz";
  };
in
pkgs.stdenv.mkDerivation rec {
  inherit version shortVersion;
  pname = "julia";
  src = pkgs.fetchurl {
    inherit url sha256;
  };
  buildInputs = [ pkgs.undmg ];
  sourceRoot = ".";
  phases = [ "unpackPhase" "installPhase" ];
  undmg = true;
  installPhase = ''
    cp -r ./Julia-${shortVersion}.app/Contents/Resources/julia $out
  '';
}
