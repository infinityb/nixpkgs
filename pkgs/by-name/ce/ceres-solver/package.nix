{
  lib,
  stdenv,
  fetchurl,
  blas,
  cmake,
  eigen,
  gflags,
  glog,
  suitesparse,
  metis,
  runTests ? false,
  enableStatic ? stdenv.hostPlatform.isStatic,
  withBlas ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ceres-solver";
  version = "2.1.0";

  # ceres-solver.org no longer serves anything: its authoritative A record
  # (66.175.223.105) resolves fine but accepts no connection on 80 or 443, and
  # probes from unrelated networks fail the same way (HTTP 522 origin timeout),
  # so this is not a local IPv4/IPv6 problem. The project publishes no GitHub
  # release assets, but the byte-identical 2.1.0 tarball is on the NixOS hashed
  # mirror, so fetch it there and keep the original host as a fallback.
  src = fetchurl {
    # Needed because the mirrored URL's basename is the hash, not the filename.
    name = "ceres-solver-${finalAttrs.version}.tar.gz";
    urls = [
      "https://tarballs.nixos.org/sha256/1iig3rq8cch7ly3ikkkby5mnmq8zs28qri0yqnzpbv8avvn4xmzp"
      "http://ceres-solver.org/ceres-solver-${finalAttrs.version}.tar.gz"
    ];
    sha256 = "sha256-99dO7N4K7XW/xR7EjJHQH+Fqa/FrzhmHpwcyhnAeL8Y=";
  };

  outputs = [
    "out"
    "dev"
  ];

  nativeBuildInputs = [ cmake ];
  buildInputs = lib.optional runTests gflags;
  propagatedBuildInputs = [
    eigen
    glog
  ]
  ++ lib.optionals withBlas [
    blas
    suitesparse
    metis
  ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=${if enableStatic then "OFF" else "ON"}"
  ];

  # The Basel BUILD file conflicts with the cmake build directory on
  # case-insensitive filesystems, eg. darwin.
  preConfigure = ''
    rm BUILD
  '';

  doCheck = runTests;

  checkTarget = "test";

  meta = {
    description = "C++ library for modeling and solving large, complicated optimization problems";
    license = lib.licenses.bsd3;
    homepage = "http://ceres-solver.org";
    maintainers = with lib.maintainers; [ giogadi ];
    platforms = lib.platforms.unix;
  };
})
