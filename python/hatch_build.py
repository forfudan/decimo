"""Tell hatchling this wheel is not pure Python.

The package carries a compiled extension and the Mojo runtime libraries beside
it, so the wheel has to be tagged for the interpreter and platform it was built
for. Without this hook hatchling would tag it `py3-none-any`, and pip would
happily install a macOS arm64 binary on a Linux box.
"""

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version, build_data):
        build_data["pure_python"] = False
        build_data["infer_tag"] = True
