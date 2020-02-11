{
  description = "A tool for deploying NixOS machines in a network or cloud";

  edition = 201909;

  inputs.nixops-aws = {
    uri = github:kreisys/nixops-aws;
    flake = false;
  };

  inputs.nixops-hetzner = {
    uri = github:NixOS/nixops-hetzner;
    flake = false;
  };

  outputs = { self, nixpkgs, nixops-aws, nixops-hetzner }:
    let

      systems = [ "x86_64-linux" "x86_64-darwin" ];

      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f system);

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };

      officialRelease = true;

      version = "1.7" + (if officialRelease then "" else "pre${builtins.substring 0 8 self.lastModified}.${self.shortRev}");

      pkgs = pkgsFor "x86_64-linux";

    in {

      overlay = final: prev: {

        nixops = with final; python2Packages.buildPythonApplication rec {
          name = "nixops-${version}";

          src = "${self.hydraJobs.tarball}/tarballs/*.tar.bz2";

          buildInputs = [ python2Packages.nose python2Packages.coverage ];

          nativeBuildInputs = [ mypy ];

          propagatedBuildInputs = with python2Packages;
            [ prettytable
              # Go back to sqlite once Python 2.7.13 is released
              pysqlite
              typing
              pluggy
              (import (nixops-aws + "/release.nix") {
                inherit nixpkgs;
                src = nixops-aws;
              }).build.${final.system}
              (import (nixops-hetzner + "/release.nix") {
                inherit nixpkgs;
                src = nixops-hetzner;
              }).build.${final.system}
            ];

          # For "nix dev-shell".
          shellHook = ''
            export PYTHONPATH=$(pwd):$PYTHONPATH
            export PATH=$(pwd)/scripts:${openssh}/bin:$PATH
          '';

          doCheck = true;

          postCheck = ''
            # We have to unset PYTHONPATH here since it will pick enum34 which collides
            # with python3 own module. This can be removed when nixops is ported to python3.
            PYTHONPATH= mypy --cache-dir=/dev/null nixops
            # smoke test
            HOME=$TMPDIR $out/bin/nixops --version
          '';

          # Needed by libcloud during tests.
          SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

          # Add openssh to nixops' PATH. On some platforms, e.g. CentOS and RHEL
          # the version of openssh is causing errors with big networks (40+).
          makeWrapperArgs = ["--prefix" "PATH" ":" "${openssh}/bin" "--set" "PYTHONPATH" ":"];

          postInstall =
            ''
              # Backward compatibility symlink.
              ln -s nixops $out/bin/charon

              make -C doc/manual install \
                docdir=$out/share/doc/nixops mandir=$out/share/man

              mkdir -p $out/share/nix/nixops
              cp -av nix/* $out/share/nix/nixops
            '';
        };

      };

      hydraJobs = {

        build = forAllSystems (system: (pkgsFor system).nixops);

        tarball = pkgs.releaseTools.sourceTarball {
          name = "nixops-tarball";

          src = self;

          inherit version;

          officialRelease = true; # hack

          buildInputs = [ pkgs.git pkgs.libxslt pkgs.docbook5_xsl ];

          postUnpack = ''
            # Clean up when building from a working tree.
            if [ -d $sourceRoot/.git ]; then
              (cd $sourceRoot && (git ls-files -o | xargs -r rm -v))
            fi
          '';

          distPhase =
            ''
              # Generate the manual and the man page.
              cp ${(import ./doc/manual { revision = self.rev; inherit nixpkgs; }).optionsDocBook} doc/manual/machine-options.xml

              for i in scripts/nixops setup.py doc/manual/manual.xml; do
                substituteInPlace $i --subst-var-by version ${version}
              done

              make -C doc/manual install docdir=$out/manual mandir=$TMPDIR/man

              releaseName=nixops-$VERSION
              mkdir ../$releaseName
              cp -prd . ../$releaseName
              rm -rf ../$releaseName/.git
              mkdir $out/tarballs
              tar  cvfj $out/tarballs/$releaseName.tar.bz2 -C .. $releaseName

              echo "doc manual $out/manual manual.html" >> $out/nix-support/hydra-build-products
            '';
        };

        tests.none_backend = (import ./tests/none-backend.nix {
          inherit nixpkgs;
          nixops = pkgs.nixops;
          system = "x86_64-linux";
        }).test;
      };

      checks.build = self.hydraJobs.build.x86_64-linux;

      packages = forAllSystems (system: {
        inherit (pkgsFor system) nixops;
      });

      defaultPackage = forAllSystems (system: self.packages.${system}.nixops);

    };
}
