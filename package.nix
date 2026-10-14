{
  buildGoModule,
  fetchFromGitHub,
  lib,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "APS2api";
  version = "11b1f3b";

  src = fetchFromGitHub {
    owner = "DeconstructedCube";
    repo = "APS2api";
    rev = "${finalAttrs.version}";
    hash = "sha256-3k5MuBwCRe4pn+A0KQSckStw4V1TUq5gNC3G0W41u2k=";
  };
  subPackages = ["cmd/vproxy"];

  postInstall = ''
    mv $out/bin/vproxy $out/bin/vertex-proxy
  '';

  vendorHash = "sha256-8dcoL3trn2exSNHDB2Tc3arAuI2Ub17fx+3bhQMgVh8=";

  meta = {
    mainProgram = "vertex-proxy";
    description = "Agent Platform Studio to api";
    homepage = "https://github.com/DeconstructedCube/APS2api";
    license = lib.licenses.mkLicense {
      shortName = "PolyForm-Noncommercial-1.0.0";
      fullName = "PolyForm Noncommercial License 1.0.0";
      spdxId = "PolyForm-Noncommercial-1.0.0";
    };
  };
})
