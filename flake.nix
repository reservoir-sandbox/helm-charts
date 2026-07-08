{
  description = "Среда разработки для Helm-чартов";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # Функция генерирует правильную структуру: [attr].[system].[name]
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
    in
    {
      # Теперь devShells корректно разворачивается в devShells.x86_64-linux.default
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              kubernetes-helm
              helm-docs
              chart-testing
              kube-linter
              kustomize
              yamllint
              yq
              git
              go
              go-task
            ];

            shellHook = ''
              echo "🚀 Helm Chart Dev Environment initialized!"
              echo "Helm version: $(helm version --short)"
            '';
          };
        });
    };
}
