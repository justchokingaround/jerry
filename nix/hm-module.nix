self: {
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkPackageOption mkOption types mkIf literalExpression;

  packages = self.packages.${pkgs.stdenvh.hostPlatform.system};

  cfg = config.programs.jerry;
in {
  options = {
    programs.jerry = {
      enable = mkEnableOption "jerry";
      package = mkPackageOption packages "jerry" {
        default = "default";
        pkgsText = "jerry.packages.\${pkgs.stdenv.hostPlatform.system}";
      };

      config = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Configuration written to `$XDG_CONFIG_HOME/jerry/jerry.conf`.
          Booleans have to be passed as literal strings, e.g.: "true" or "false"

          See <https://github.com/justchokingaround/jerry/blob/main/examples/jerry.conf> for the full list of options.
        '';
        example = literalExpression ''
          {
            provider = "yugen";
            score_on_completion = "true";
          }
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

    xdg.configFile."jerry/jerry.conf".text = mkIf (cfg.config != {}) (lib.toShellVars cfg.config);
  };
}
