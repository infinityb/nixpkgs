{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  bison,
  flex,
  asciidoc,
  libxslt,
  findXMLCatalogs,
  docbook_xml_dtd_45,
  docbook_xsl,
  libmnl,
  libnftnl,
  libpcap,
  gmp,
  jansson,
  autoreconfHook,
  withDebugSymbols ? false,
  withCli ? true,
  libedit,
  withXtables ? true,
  iptables,
  nixosTests,
  gitUpdater,
  ncurses,
}:

stdenv.mkDerivation rec {
  version = "1.1.6";
  pname = "nftables";

  src = fetchurl {
    url = "https://netfilter.org/projects/nftables/files/${pname}-${version}.tar.xz";
    hash = "sha256-NykxvahVazEGNqL5AgrccQ+bq2b0fv4M6Qv/gArCUww=";
  };

  patches = [
    (fetchurl {
      name = "musl.patch";
      url = "https://lore.kernel.org/netfilter-devel/20241219231001.1166085-2-hi@alyssa.is/raw";
      hash = "sha256-7vMBIoDWcI/JBInYP5yYWp8BnYbATRfMTxqyZr2L9Sk=";
    })

    # Following 4 commits fix reproducibility.  They are upstream commits
    # 2e3c68f26d5bd60c8ea7467fa9018c282a7d8c47, 2a0ec8a7246e5c5eb85270e3d4de43e20a00c577,
    # b92571cc59ce49fdd9fe2daac9350529adfb2424 and
    # ca86f206c92704170a295b8dc7a41f6448835dde, and they are all merged for
    # nftables 1.1.7, so they can be dropped once this package is updated.
    #
    # They used to be fetched from
    # https://git.netfilter.org/nftables/patch/?id=<commit>, but that cgit
    # endpoint now replies to such requests with a JavaScript anti-bot
    # challenge page ("Making sure you're not a bot!") instead of the generated
    # patch: the bytes differ on every request, so no recorded hash can ever
    # match and the fetches are unusable.  They are kept in-tree instead, as
    # `git format-patch -1 <commit>` output taken from the upstream repository
    # at https://git.netfilter.org/nftables (git over https still works).
    ./0001-build-fix-.-configure-with-non-bash-shell.patch
    ./0002-build-simplify-the-instantation-of-nftversion.h.patch
    ./0003-build-generate-build-time-stamp-once-at-configure.patch
    ./0004-build-support-SOURCE_DATE_EPOCH-for-build-time-stamp.patch
  ];

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    bison
    flex
    asciidoc
    docbook_xml_dtd_45
    docbook_xsl
    findXMLCatalogs
    libxslt
  ]
  ++ lib.optional stdenv.hostPlatform.isStatic ncurses;

  buildInputs = [
    libmnl
    libnftnl
    libpcap
    gmp
    jansson
  ]
  ++ lib.optional withCli libedit
  ++ lib.optional withXtables iptables;

  env.NIX_LDFLAGS = lib.optionalString stdenv.hostPlatform.isStatic "-lncursesw";

  configureFlags = [
    "--with-json"
    (lib.withFeatureAs withCli "cli" "editline")
  ]
  ++ lib.optional (!withDebugSymbols) "--disable-debug"
  ++ lib.optional withXtables "--with-xtables";

  enableParallelBuilding = true;

  passthru.tests = {
    inherit (nixosTests) firewall-nftables;
    nat = { inherit (nixosTests.nat.nftables) firewall standalone; };
  };

  passthru.updateScript = gitUpdater {
    url = "https://git.netfilter.org/nftables";
    rev-prefix = "v";
  };

  meta = {
    description = "Project that aims to replace the existing {ip,ip6,arp,eb}tables framework";
    homepage = "https://netfilter.org/projects/nftables/";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ izorkin ];
    mainProgram = "nft";
  };
}
