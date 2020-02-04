# Top level hercules-ci description.
{
  # build all packages (on and for) linux
  x86_64-linux = import ./. { system = "x86_64-linux"; };
  # build all packages (on and for) macos
  x86_64-macos = import ./. { system = "x86_64-darwin"; };
  # build all packages on linux for windows
  x86_64-mingw = import ./. { system = "x86_64-linux"; crossSystem = "x86_64-w64-mingw32"; };
  # build all docker inputs
  docker-inputs = (import ./docker {}).hydraJob;
}
