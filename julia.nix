{ pkgs, system }:
let
  version = "1.8.2";
  shortVersion = "1.8";
  sha256 = builtins.getAttr system {
    # Use nix-prefetch-url https://julialang-s3.julialang.org/bin/linux/x64/1.8/julia-1.8.2-linux-x86_64.tar.gz
    "aarch64-darwin" = "19csaidzkcxbpbms75y8vwfz4lxwxxkzhm5iaf8m2ksi9vgd7wh6";
    "x86_64-linux" = "15p70ly9mw9896snq51fbc0nz1g3hy8gdmzd3rz72fmna2jg6737";
    # "x86_64-linux" = "0jp06dzzrvm0fxqcvxr83zc0x2s0ys1vj72fwy5mhjr5607zjl4s";
  };
  url = builtins.getAttr system {
    "aarch64-darwin" = "https://julialang-s3.julialang.org/bin/mac/aarch64/${shortVersion}/julia-${version}-macaarch64.dmg";
    "x86_64-linux" = "https://julialang-s3.julialang.org/bin/linux/x64/${shortVersion}/julia-${version}-linux-x86_64.tar.gz";
    # "x86_64-linux" = "https://julialang-s3.julialang.org/bin/musl/x64/${shortVersion}/julia-${version}-musl-x86_64.tar.gz";
  };

  os = builtins.elemAt (builtins.split "-" system) 2;
in
if os == "linux" then pkgs.callPackage (import ./julia-linux.nix) { } else
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

