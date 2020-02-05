{ system  ? builtins.currentSystem
, nixpkgs ? <nixpkgs>
, pkgs    ? import nixpkgs { inherit system; }
, nixops  ? (import ../release.nix { nixpkgs = pkgs.path; p = (p: [
  # (p.callPackage ../../nixops-aws/release.nix { officialRelease = true; })
    p.aws
  ]); }).build.${system}
, networkExprs
, checkConfigurationOptions ? true
, uuid
, deploymentName
, args
, pluginNixExprs ?
  with pkgs; with lib; pipe nixops.propagatedBuildInputs [
    (filter ({ name, ... }: hasPrefix "nixops-" name))
    (map (plugin: plugin + "/share/nix/${getName plugin}"))
  ]
}:

with pkgs;
with lib;

rec {
  inherit pluginNixExprs networkExprs;

  importedPluginNixExprs          = map (expr: import expr) pluginNixExprs;
  pluginResources                 = map (e: e.resources) importedPluginNixExprs;
  pluginOptions                   = { imports = (foldl (a: e: a ++ e.options) [] importedPluginNixExprs); };
  pluginDeploymentConfigExporters = (foldl (a: e: a ++ (e.config_exporters { inherit optionalAttrs pkgs; })) [] importedPluginNixExprs);

  network = let
    baseModules = import (pkgs.path + "/nixos/modules/module-list.nix");

    call = e: rec {
      lambda = e args;
      set    = e;
      path   = string;
      string = {
        _file = e;
        imports = [ (call (import e)) ];
      };
    }.${builtins.typeOf e};

  in (evalModules {
    modules = [
      ./network.nix
      {
        _module.args = {
          inherit args pkgs baseModules pluginOptions pluginResources deploymentName uuid pluginDeploymentConfigExporters;
        } // args;
      }
    ] ++ (map call networkExprs);
  }).config;

  inherit (network) defaults nodes resources;

  # Phase 1: evaluate only the deployment attributes.
  info =
    let
      network' = network;
      resources' = resources;
    in rec {

      machines =
        flip mapAttrs nodes (n: v': let
          v = scrubOptionValue v';

        in foldr (a: b: a // b) {
          inherit (v.deployment) targetEnv targetPort targetHost encryptedLinksTo storeKeysOnMachine alwaysActivate owners keys hasFastConnection;
          nixosRelease = v.system.nixos.release or v.system.nixosRelease or (removeSuffix v.system.nixosVersionSuffix v.system.nixosVersion);
          publicIPv4 = v.networking.publicIPv4;
        } (map (f: f v) pluginDeploymentConfigExporters));

    inherit (network') network;

    resources = removeAttrs resources' [ "machines" ];
  };

  # Phase 2: build complete machine configurations.
  machines = { names }: let
    nodes' = filterAttrs (n: v: elem n names) nodes;

  in runCommand "nixops-machines" {
    preferLocalBuild = true;
  } ''
    mkdir -p $out
    ${toString (attrValues (mapAttrs (n: v: ''
      ln -s ${v.system.build.toplevel} $out/${n}
    '') nodes'))}
  '';


  # Function needed to calculate the nixops arguments. This should work even when arguments
  # are not set yet, so we fake arguments to be able to evaluate the require attribute of
  # the nixops network expressions.

  dummyArgs = f: builtins.listToAttrs (map (a: lib.nameValuePair a false) (builtins.attrNames (builtins.functionArgs f)));

  getNixOpsExprs = l: lib.unique (lib.flatten (map getRequires l));

  getRequires = f:
    let
      nixopsExpr = import f;
      requires =
        if builtins.isFunction nixopsExpr then
          ((nixopsExpr (dummyArgs nixopsExpr)).require or [])
        else
          (nixopsExpr.require or []);
    in
      [ f ] ++ map getRequires requires;

  fileToArgs = f:
    let
      nixopsExpr = import f;
    in
      if builtins.isFunction nixopsExpr then
        map (a: { "${a}" = builtins.toString f; } ) (builtins.attrNames (builtins.functionArgs nixopsExpr))
      else [];

  getNixOpsArgs = fs: lib.zipAttrs (lib.unique (lib.concatMap fileToArgs (getNixOpsExprs fs)));

  nixopsArguments = getNixOpsArgs networkExprs;
}
