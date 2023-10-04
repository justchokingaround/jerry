{ coreutils,
  curl,
  fetchFromGitHub,
  ffmpeg,
  fzf,
  gnugrep,
  gnupatch,
  gnused,
  html-xml-utils,
  lib,
  makeWrapper,
  mpv,
  openssl,
  stdenv,
  testers,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "jerry";
  version = "1.9.9";

  src = ./.;

  nativeBuildInputs = [
    coreutils # wc
    curl
    ffmpeg
    fzf
    gnugrep
    gnupatch
    gnused
    html-xml-utils
    makeWrapper
    mpv
    openssl
  ];

  installPhase = ''
      mkdir -p $out/bin
      cp jerry.sh $out/bin/jerry
      wrapProgram $out/bin/jerry \
        --prefix PATH : ${lib.makeBinPath [
          coreutils
          curl
          ffmpeg
          fzf
          gnugrep
          gnupatch
          gnused
          html-xml-utils
          mpv
          openssl
        ]}
    '';

  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
  };

  meta = with lib; {
    description = "watch anime with automatic anilist syncing and other cool stuff";
    homepage = "https://github.com/justchokingaround/jerry";
    license = licenses.gpl3;
    maintainers = with maintainers; [ justchokingaround ];
    platforms = platforms.unix;
  };
})
