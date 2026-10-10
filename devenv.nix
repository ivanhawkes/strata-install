{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  # CUDA build of llama-cpp. The explicit override is what enables CUDA;
  # the top-level pkgs already has allowUnfree set by devenv (devenv.yaml).
  llamaCppPackage = pkgs.llama-cpp.override { cudaSupport = true; };

  # Native local GPU inference wrapper
  runServer = pkgs.writeShellScriptBin "strata" ''
    export CUDA_DEVICE_ORDER=PCI_BUS_ID
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib:$LD_LIBRARY_PATH"
  
  # TODO: Run the strata server here.

  '';

in
{
  # Node JS
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_24;
  };
  
  # Python
  languages.python = {
    enable = true;
    package = pkgs.python3;
    venv = {
      enable = true;
      quiet = true;
      requirements = ''
        # If installing via pip package or repository
        git+https://github.com
      '';
    };
  };

  # Go
  languages.go = {
    enable = true;
    package = pkgs.go;
  };

  # 2. System Packages & Git Tooling
  packages = [
    runServer

    pkgs.fastfetch
    pkgs.curl
    pkgs.git
    pkgs.git-lfs
    pkgs.gh

    # CUDA needed for some build processes.
    pkgs.cudaPackages.cuda_nvcc
    pkgs.cudaPackages.cudatoolkit
    pkgs.cudaPackages.backendStdenv

    # Pi harness (pi coding agent CLI, v1.0 in nixos-unstable)
    pkgs.pi-coding-agent
    pkgs.linuxPackages.nvidia_x11.open

    # Wayland clipboard copy and paste at the command line.
    pkgs.wl-clipboard
  ];

  # Environment Variables (Add the Wayland passthrough here)
  env = {
    TMPDIR = "/tmp";

    # Pass through Wayland & Noctalia / Niri environment contexts/
    WAYLAND_DISPLAY = "wayland-1";
    
    # Fallback for XWayland bridges inside the shell
    DISPLAY = ":0";

    # These are required to build Strata.
    # CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
    # CUDA_CACHE_PATH = "$HOME/.nv/ComputeCache";
    # LD_LIBRARY_PATH = "${pkgs.linuxPackages.nvidia_x11}/lib:${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64";
    
    # Optimized compilation for the RTX 5060 Ti
    # CMAKE_ARGS = "-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120";
  };

  # Enable the native delta integration for improved Git diff views.
  delta.enable = true;

  enterShell = ''
    # Automatically localise Git LFS constraints
    git lfs install --local 2>/dev/null || true

    echo "💡 Type 'strata' to instantly start your engine via native CUDA acceleration."
    echo "🚀 Devenv active: Node.js 24, Python 3, Go, and Git tools are ready."
  '';
}
