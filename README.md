# NixOps

NixOps (formerly known as Charon) is a tool for deploying NixOS
machines in a network or cloud.

* [Manual](https://nixos.org/nixops/manual/)
* [Installation](https://nixos.org/nixops/manual/#chap-installation) / [Hacking](https://nixos.org/nixops/manual/#chap-hacking)
* [Continuous build](http://hydra.nixos.org/jobset/nixops/master#tabs-jobs)
* [Source code](https://github.com/NixOS/nixops)
* [Issue Tracker](https://github.com/NixOS/nixops/issues)
* [Mailing list / Google group](https://groups.google.com/forum/#!forum/nixops-users)
* [IRC - #nixos on freenode.net](irc://irc.freenode.net/#nixos)

## Developing

To start developing on nixops, you can run:

```bash
  $ nix dev-shell
```

Where plugin1 can be any available nixops plugin, and where
none or more than one can be specified, including local plugins.
An example is:


```bash
  $ ./dev-shell --arg p "(p: [ p.aws p.hetzner (p.callPackage ../myplugin/release.nix {})])"
```

Available plugins, such as "aws" and "hetzner" in the example
above, are the plugin attribute names found in the data.nix file.

To update the available nixops plugins found in github repositories,
edit the all-plugins.txt file with any new github plugin repositories
that are available and then execute the update-all script.  This will
refresh the data.nix file, providing new plugin attributes to use.

Local nixops plugins, such as the `callPackage ../myplugin/release.nix {}`
example seen above, have no need to be in the all-plugins.txt
or data.nix file.

## Building from source

The command to build NixOps depends on your platform and which plugins you choose:

- `nix build .#hydraJobs.build.x86_64-linux` on 64 bit linux.
- `nix-build .#hydraJobs.build.i686-linux` on 32 bit linux.
- `nix-build .#hydraJobs.build.x86_64-darwin` on OSX.

NixOps can be imported into another flake as follows:

```nix
{
  edition = 201909;

  inputs.nixops.uri = github:NixOS/nixops;

  outputs = { self, nixpkgs, nixops }: {
    packages.my-package =
      let
        pkgs = import nixpkgs {
          system = "x86_linux";
          overlays = [ nixops.overlay ];
        };
      in
        pkgs.stdenv.mkDerivation {
          ...
          buildInputs = [ pkgs.nixops ];
        };
  };
}
```
