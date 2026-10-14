{
  buildGoModule,
  fetchFromGitHub,
  lib,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "APS2api";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "DeconstructedCube";
    repo = "APS2api";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HLL0O0V+jecgjQ5ePWj5BBIdwau2+QGOAo3iuFCLXN0=";
  };
  subPackages = ["cmd/vproxy"];
  env = {
    GOFLAGS = "-o=vertex-proxy";
  };

  postInstall = ''
    mv $out/bin/vproxy $out/bin/vertex-proxy
  '';

  vendorHash = "sha256-qwocsXP0OBuDS1MbJ1UnVp1dpJ5m+36fA+gBYsEfed0=";

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
