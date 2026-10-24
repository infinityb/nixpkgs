{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation (finalAttrs: {
  version = "2.8.7";
  pname = "tinygltf";

  src = fetchFromGitHub {
    owner = "syoyo";
    repo = "tinygltf";
    tag = "v${finalAttrs.version}";
    # The tag never moved (target 753576f8, Apr 2023, its parent is the commit
    # tagged v2.8.6), but the tarball GitHub serves for it today is not the one
    # that was served when the hash below was recorded in Apr 2023. Recomputed
    # with `nix hash path` on the extracted archive, which `diff -ruN` shows is
    # identical to a clone of the tag.
    hash = "sha256-V4d4n1gBNcwiqBQlUn9q5h9+SAchELg4V3ih9WPEWbw=";
  };

  nativeBuildInputs = [ cmake ];

  meta = {
    description = "Header only C++11 tiny glTF 2.0 library";
    homepage = "https://github.com/syoyo/tinygltf";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      yzx9
    ];
    platforms = lib.platforms.all;
  };
})
