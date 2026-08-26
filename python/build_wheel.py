"""Build a self-contained decimo wheel, and optionally upload it.

Run it through pixi, which puts the build tools on the path:

    pixi run release                  # build the wheel, stop there
    pixi run release --testpypi       # ... and upload to TestPyPI
    pixi run release --pypi           # ... and upload to PyPI
    pixi run release --version 0.2.0  # a real version instead of a dev stamp

The version defaults to `0.1.0.devYYYYMMDDHHMMSS` in UTC. PyPI refuses to
accept the same version twice, so a timestamp means every build during
development has somewhere to go.

The interesting part is the vendoring. `_decimo.so` does not stand alone: it
loads three Mojo runtime libraries through an `@rpath` that points at the pixi
environment on the machine that built it. A wheel with that path in it works
only here. So the libraries are copied in next to the extension and every
`@rpath` is rewritten to `@loader_path`, which means "the directory I am in".
Together they come to about 1.6 MB.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE / "src" / "decimo"
REPOSITORY = HERE.parent
ENVIRONMENT_LIBRARY = REPOSITORY / ".pixi" / "envs" / "default" / "lib"


def run(command, **kwargs):
    print("  $", " ".join(str(part) for part in command))
    return subprocess.run(command, check=True, **kwargs)


def dependencies_of(binary):
    """The `@rpath/...` libraries a Mach-O file loads."""
    output = subprocess.run(
        ["otool", "-L", str(binary)], capture_output=True, text=True, check=True
    ).stdout
    found = []
    for line in output.splitlines()[1:]:
        name = line.strip().split(" ")[0]
        if name.startswith("@rpath/"):
            found.append(name[len("@rpath/") :])
    return found


def existing_rpaths(binary):
    output = subprocess.run(
        ["otool", "-l", str(binary)], capture_output=True, text=True, check=True
    ).stdout
    return re.findall(r"path (.+) \(offset \d+\)", output)


def point_at_own_directory(binary):
    """Rewrite the load paths so the file looks beside itself, not at pixi.

    Editing a Mach-O file invalidates its code signature, and macOS answers an
    invalid signature by killing the process outright -- no exception, no
    message, just SIGKILL on import. So every file that is touched is re-signed
    ad-hoc afterwards. Skipping this produced a wheel that imported fine while
    the pixi environment was present and died silently anywhere else.
    """
    for path in existing_rpaths(binary):
        if path == "@loader_path":
            continue
        subprocess.run(
            ["install_name_tool", "-delete_rpath", path, str(binary)],
            check=True,
            capture_output=True,
        )
    if "@loader_path" not in existing_rpaths(binary):
        run(["install_name_tool", "-add_rpath", "@loader_path", str(binary)])
    run(["codesign", "--force", "--sign", "-", str(binary)])


def vendor_runtime():
    """Copy the Mojo runtime libraries into the package and re-point them."""
    extension = PACKAGE / "_decimo.so"
    if not extension.exists():
        sys.exit(
            f"{extension} is missing -- run `pixi run buildpy` first "
            "(the `release` task normally does that for you)."
        )
    if sys.platform != "darwin":
        sys.exit(
            "Vendoring is written for macOS (otool / install_name_tool).\n"
            "On Linux the same job is done by `auditwheel repair`, which "
            "this script does not call yet."
        )

    # Start from a clean package directory. Leaving last run's libraries in
    # place would skip them here and, worse, leave them unsigned after the
    # extension beside them was rebuilt.
    for stale in PACKAGE.glob("*.dylib"):
        stale.unlink()

    copied = []
    pending = [extension]
    while pending:
        binary = pending.pop()
        for name in dependencies_of(binary):
            destination = PACKAGE / name
            if destination.exists():
                continue
            source = ENVIRONMENT_LIBRARY / name
            if not source.exists():
                sys.exit(f"cannot find {name} in {ENVIRONMENT_LIBRARY}")
            shutil.copy2(source, destination)
            destination.chmod(0o755)
            copied.append(destination)
            pending.append(destination)

    for binary in [extension, *copied]:
        point_at_own_directory(binary)

    total = sum(path.stat().st_size for path in copied)
    print(f"  vendored {len(copied)} libraries, {total / 1e6:.2f} MB")
    return copied


def write_version(version):
    (PACKAGE / "_version.py").write_text(
        '"""Written by `pixi run release`. Do not edit."""\n\n'
        f'__version__ = "{version}"\n'
    )
    print(f"  version {version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version",
        help="version to stamp (default: 0.1.0.devYYYYMMDDHHMMSS, UTC)",
    )
    parser.add_argument(
        "--pypi", action="store_true", help="upload to PyPI when the build works"
    )
    parser.add_argument(
        "--testpypi", action="store_true", help="upload to TestPyPI instead"
    )
    arguments = parser.parse_args()

    if arguments.pypi and arguments.testpypi:
        sys.exit("choose one of --pypi and --testpypi, not both")

    version = arguments.version or datetime.now(timezone.utc).strftime(
        "0.1.0.dev%Y%m%d%H%M%S"
    )

    print("Preparing the package")
    write_version(version)
    vendor_runtime()

    distribution = HERE / "dist"
    if distribution.exists():
        shutil.rmtree(distribution)

    print("Building the wheel")
    run(
        [sys.executable, "-m", "build", "--wheel", "--outdir", str(distribution)],
        cwd=HERE,
    )

    wheels = sorted(distribution.glob("*.whl"))
    if not wheels:
        sys.exit("no wheel was produced")
    wheel = wheels[-1]
    print(f"\n  {wheel}  ({wheel.stat().st_size / 1e6:.2f} MB)")

    print("\nChecking the metadata")
    run([sys.executable, "-m", "twine", "check", str(wheel)])

    if not (arguments.pypi or arguments.testpypi):
        print(
            "\nBuilt, not uploaded. Add --testpypi or --pypi to upload.\n"
            "Install it here to try it out:\n"
            f"  pip install --force-reinstall {wheel}"
        )
        return 0

    target = "testpypi" if arguments.testpypi else "pypi"
    if not (os.environ.get("TWINE_PASSWORD") or os.environ.get("TWINE_API_KEY")):
        print(
            f"\nAbout to upload to {target}. twine will ask for a token, or "
            "you can set TWINE_USERNAME=__token__ and TWINE_PASSWORD=pypi-..."
        )
    print(f"\nUploading to {target}")
    command = [sys.executable, "-m", "twine", "upload"]
    if arguments.testpypi:
        command += ["--repository", "testpypi"]
    command.append(str(wheel))
    run(command)
    print(f"\nUploaded {wheel.name} to {target}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
