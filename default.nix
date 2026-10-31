{
  pkgs,
  lib ? pkgs.lib,
}:
let
  mkExeName = pkg: if pkg == null then null else pkg.meta.mainProgram or (lib.getName pkg);

  mkShareFiles =
    pkg:
    pkgs.runCommand "${lib.getName pkg}-share" { } ''
      mkdir -p $out/share
      for d in applications icons pixmaps mime metainfo; do
        if [[ -e ${pkg}/share/$d ]]; then
          cp -rL --no-preserve=mode ${pkg}/share/$d $out/share/
        fi
      done
    '';

  lazy-app = lib.makeOverridable (
    {
      pkg ? pkgs.hello,
      exe ? mkExeName pkg,
      desktopItem ? null, # Deprecate desktopItem?
      desktopItems ? [ ],
    }:
    pkgs.runCommand "lazy-${exe}"
      (
        let
          exePath = if exe != null then lib.getExe' pkg exe else lib.getExe pkg;

          notify-send = lib.getExe pkgs.libnotify;
        in
        {
          pname = lib.getName pkg;
          version = lib.getVersion pkg;
          nativeBuildInputs = with pkgs; [
            copyDesktopItems
            rsync
          ];

          desktopItems = desktopItems ++ lib.optional (desktopItem != null) desktopItem;

          meta.mainProgram = exe;

          script = ''
            #!${pkgs.runtimeShell}

            set -euo pipefail

            app='${exe}'
            path='${builtins.unsafeDiscardStringContext exePath}'

            if [[ ! -e $path ]]; then
                noteId=$(${notify-send} -t 0 -p "Realizing $app …")
                trap "${notify-send} -r '$noteId' 'Canceled realization of $app'" EXIT
                SECONDS=0
                nix-store --realise "$path" > /dev/null 2>&1
                trap - EXIT
                ${notify-send} -r "$noteId" "Realized $app in $SECONDS s"
            fi

            if [[ -e $path ]]; then
                exec $path "$@"
            fi
          '';
          exeName = exe;
          passAsFile = [ "script" ];
        }
      )
      ''
        runHook preInstall
        mkdir -p $out/share
        rsync -r --chmod=Du+rwx,Fu+rw ${mkShareFiles pkg}/share/ $out/share/
        install -Dm755 "$scriptPath" "$out/bin/$exeName"
        runHook postInstall
      ''
  ) { };
in
lazy-app
