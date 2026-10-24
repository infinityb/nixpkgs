{
  lib,

  stdenv,
  fetchFromGitHub,
  nix-update-script,

  # nativeBuildInputs
  cmake,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tinygltf";
  version = "3.0.0";

  strictDeps = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "syoyo";
    repo = "tinygltf";
    tag = "v${finalAttrs.version}";
    # GitHub now serves a different archive for this (unmoved) tag than it did
    # when the hash below was recorded, so the old value no longer matches.
    # Recomputed with `nix hash path` on the extracted archive, which matches a
    # clone of the tag.
    hash = "sha256-HY/ZwqukHcFE181B12AH5uYCXypWRqBRbXZ0+t3yKbc=";
  };

  nativeBuildInputs = [
    cmake
  ];

  cmakeFlags = [
    # unvendoring will break downstream applications
    # unless at least patch the CMake modules
    (lib.cmakeBool "TINYGLTF_INSTALL_VENDOR" true)
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Header only C++11 tiny glTF 2.0 library";
    homepage = "https://github.com/syoyo/tinygltf";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ nim65s ];
    platforms = lib.platforms.unix;
  };
})
