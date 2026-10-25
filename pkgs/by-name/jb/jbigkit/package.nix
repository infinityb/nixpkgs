{
  lib,
  stdenv,
  fetchurl,
  fetchpatch,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "jbigkit";
  version = "2.1";

  src = fetchurl {
    url = "https://www.cl.cam.ac.uk/~mgk25/jbigkit/download/jbigkit-${finalAttrs.version}.tar.gz";
    hash = "sha256-3nEGtr+vSV1oZcfdesbKE4G9EuDYFAXqgefyFnJj2TI=";
  };

  # The Archlinux patches below live in Arch's packaging repo. Arch deleted all
  # of the 2.1-era ones from its default branch when it bumped the package to
  # 2.2 (commit 43f4230f278f, 2026-10-12), so fetching them by branch ref 404s
  # while we still build 2.1. They are pinned to 227cd22f5001dfcfadd079dab7791d1b29ec5e7c,
  # the last commit that carried them: same bytes, immutable URL.
  patches = [
    # Archlinux patch: this helps users to reduce denial-of-service risks, as in CVE-2017-9937
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/0013-new-jbig.c-limit-s-maxmem-maximum-decoded-image-size.patch";
      hash = "sha256-Yq5qCTF7KZTrm4oeWbpctb+QLt3shJUGEReZvd0ey9k=";
    })
    # Archlinux patch: fix heap overflow
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/0015-jbg_newlen-check-for-end-of-file-within-MARKER_NEWLE.patch";
      hash = "sha256-F3qA/btR9D9NfzrNY76X4Z6vG6NrisI36SjCDjS+F5s=";
    })
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # Archlinux patch: build shared object
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/jbigkit-2.1-shared_lib.patch";
      hash = "sha256-+efeeKg3FJ/TjSOj58kD+DwnaCm3zhGzKLfUes/d5rg=";
    })
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/jbigkit-2.1-ldflags.patch";
      hash = "sha256-ik3NifyuhDHnIMTrNLAKInPgu2F5u6Gvk9daqrn8ZhY=";
    })
    # Archlinux patch: update coverity
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/jbigkit-2.1-coverity.patch";
      hash = "sha256-APm9A2f4sMufuY3cnL9HOcSCa9ov3pyzgQTTKLd49/E=";
    })
    # Archlinux patch: fix build warnings
    # Arch deleted this file from the default branch when they bumped the
    # package to 2.2 (commit 43f4230f278f, 2026-10-12), so the …/-/raw/main/…
    # URL 404s. Pin to the last commit that carried it: same bytes, stable URL.
    (fetchpatch {
      url = "https://gitlab.archlinux.org/archlinux/packaging/packages/jbigkit/-/raw/227cd22f5001dfcfadd079dab7791d1b29ec5e7c/jbigkit-2.1-build_warnings.patch";
      hash = "sha256-lDEJ1bvZ+zR7K4CiTq+aXJ8PGjILE3W13kznLLlGOOg=";
    })
  ];

  makeFlags = [
    "AR=${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ar"
    "CC=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc"
    "DESTDIR=${placeholder "out"}"
    "RANLIB=${lib.getBin stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}ranlib"
  ];

  postPatch = ''
    sed -i 's/^\(CFLAGS.*\)$/\1 -fPIC/' Makefile

    for f in Makefile libjbig/Makefile pbmtools/Makefile; do
        sed -i -E 's/\bar /$(AR) /g;s/\branlib /$(RANLIB) /g' "$f"
    done
  '';

  installPhase = ''
    runHook preInstall

    install -vDm 644 libjbig/*.h -t "$out/include/"
    install -vDm 755 pbmtools/{jbgtopbm{,85},pbmtojbg{,85}} -t "$out/bin/"
    install -vDm 644 pbmtools/*.1* -t "$out/share/man/man1/"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    install -vDm 644 libjbig/libjbig*.a -t "$out/lib/"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    install -vDm 755 libjbig/*.so.* -t "$out/lib/"

    for lib in libjbig.so libjbig85.so; do
      ln -sv "$lib.${finalAttrs.version}" "$out/lib/$lib"
      ln -sv "$out/lib/$lib.${finalAttrs.version}" "$out/lib/$lib.0"
    done
  ''
  + ''
    runHook postInstall
  '';

  doCheck = true;

  # Testing deletes all files on each test, causes test failures.
  enableParallelChecking = false;

  meta = {
    description = "Software implementation of the JBIG1 data compression standard";
    homepage = "http://www.cl.cam.ac.uk/~mgk25/jbigkit/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.all;
  };
})
