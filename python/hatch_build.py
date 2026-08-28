"""Tell hatchling this wheel is not pure Python, and which platform it is for.

The package carries a compiled extension and the Mojo runtime libraries beside
it, so the wheel has to be tagged for the interpreter and platform it was built
for. Without this hook hatchling would tag it `py3-none-any`, and pip would
happily install a macOS arm64 binary on a Linux box.

The platform part is spelled out rather than inferred. Inferred, it is the
version of macOS the build ran on -- `macosx_26_0` on a current machine --
and pip then refuses the wheel on anything older. The extension is linked
for `MACOSX_DEPLOYMENT_TARGET` (14.0, set by the `release` task), so that is
what the tag says. On Linux the tag is `linux_x86_64` here and `auditwheel`
replaces it with the `manylinux` one after the build.
"""

import os
import sys
import sysconfig

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


def _platform_tag():
    if sys.platform == "darwin":
        target = os.environ.get("MACOSX_DEPLOYMENT_TARGET")
        if not target:
            # The interpreter's own target, e.g. `macosx-11.0-arm64`.
            target = sysconfig.get_platform().split("-")[1]
        major, minor = (target.split(".") + ["0"])[:2]
        machine = sysconfig.get_platform().split("-")[-1]
        return f"macosx_{major}_{minor}_{machine}"
    return sysconfig.get_platform().replace("-", "_").replace(".", "_")


def _interpreter_tag():
    return f"cp{sys.version_info.major}{sys.version_info.minor}"


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version, build_data):
        build_data["pure_python"] = False
        interpreter = _interpreter_tag()
        build_data["tag"] = f"{interpreter}-{interpreter}-{_platform_tag()}"
