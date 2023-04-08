## _isa-l_crypto_ Nuget Package

This project builds an _isa-l_crypto_ Nuget package with static
_isa-l_crypto_ libraries and header files  for the `x64` platform
and `Debug`/`Release` configurations.

Visit _isa-l_crypto_ website for additional information about the
_isa-l_crypto_ project and library documentation:

https://github.com/intel/isa-l_crypto

## Package Configuration

The _isa-l_crypto_ static library appropriate for the platform and
configuration selected in a Visual Studio solution is explicitly
referenced within this package and will appear within the solution
folder tree after the package is installed. The solution may need
to be reloaded to make the library file visible. This library may
be moved into any solution folder after the installation.

Note that the _isa-l_crypto_ library path in this package is valid
only for build configurations named `Debug` and `Release` and will
not work for any other configuration names. Do not install this
package for projects with configurations other than `Debug` and
`Release`.

## _isa-l_crypto_ Changes

_isa-l_crypto_ source that was used to create this package contains a
few changes applied in patches described in this section against the
_isa-l_crypto_ release indicated in the package version.

### `01-nmake-debug-release.patch`

This patch updates the existing `Makefile.nmake` file to allow
building `Debug` and `Release` configurations, so the appropriate
MSVC CRT version of the library is referenced in each configuration.

## Building a Nuget Package

This project can build a Nuget package for _isa-l_crypto_ either
locally or via a GitHub workflow. In each case, following steps
are taken.

  * _isa-l_crypto_ source archive is downloaded from _isa-l_crypto_'s
    website and its SHA-256 signature is verified.

  * The source is patched to build in Visual C++ 2022.

  * NASM (assembler) binaries package is downloaded the
    [NASM website][nasm.us] and its SHA-256 signature is verified.

  * VS2022 Community Edition is used to build _isa-l_crypto_ libraries
    locally and Enterprise Edition to build libraries on GitHub.

  * Build artifacts for all platforms and configurations are
    collected in staging directories under `nuget/build/native`.

  * `nuget.exe` is used to package staged files with the first
    three version components used as a _isa-l_crypto_ version and
    the last version component used as a package revision. See
    _Package Version_ section for more details.

  * The Nuget package built on GitHub is uploaded to [nuget.org][].
    The package built locally is saved in the root project
    directory.

## Package Version

### Package Revision

Nuget packages lack package revision and in order to repackage
the same upstream software version, such as _isa-l_crypto_ v2.24.0,
the 4th component of the Nuget version is used to track the Nuget
package revision.

Nuget package revision is injected outside of the Nuget package
configuration, during the package build process, and is not
present in the package specification file.

Specifically, `nuget.exe` is invoked with `-Version=2.24.0.123`
to build a package with the revision `123`.

### Version Locations

_isa-l_crypto_ version is located in a few places in this repository and
needs to be changed in all of them for a new version of _isa-l_crypto_.

  * nuget/StoneSteps.IsaLibCrypto.VS2022.Static.nuspec (`version`)
  * devops/make-package.bat (`PKG_VER`, `PKG_REV`, `ISACRYPTO_SHA256`)
  * .github/workflows/build-nuget-package.yml (`name`, `PKG_VER`,
    `PKG_REV`, `ISACRYPTO_FNAME`, `ISACRYPTO_DNAME`, `ISACRYPTO_SHA256`)

`ISACRYPTO_SHA256` ia a SHA-256 checksum of the _isa-l_crypto_ package
file and needs to be updated when a new version of _isa-l_crypto_ is
released.

NASM version is not coupled with _isa-l_crypto_'s version and needs
to be updated only when _isa-l_crypto_ changes their minimum version
requirements.

In the GitHub workflow YAML, `PKG_REV` must be reset to `1` (one)
every time _isa-l_crypto_ version is changed. The workflow file
must be renamed with the new version in the name. This is necessary
because GitHub maintains build numbers per workflow file name.

For local builds package revision is supplied on the command line
and should be specified as `1` (one) for a new version of
_isa-l_crypto_ and incremented with every package release for the
same upstream version.

### GitHub Build Number

Build number within the GitHub workflow YAML is maintained in an
unconventional way because of the lack of build maturity management
between GitHub and Nuget.

For example, using build management systems, such as Artifactory,
every build would generate a Nuget package with the same version
and package revision for the upcoming release and build numbers
would be tracked within the build management system. A build that
was successfully tested would be promoted to the production Nuget
repository without generating a new build.

Without a build management system, the GitHub workflow in this
repository uses the pre-release version as a surrogate build
number for builds that do not publish packages to nuget.org,
so these builds can be downloaded and tested before the final
build is made and published to nuget.org. This approach is not
recommended for robust production environments because even
though the final published package is built from the exact
same source, the build process may still potentially introduce 
some unknowns into the final package (e.g. build VM was updated).

## Building Package Locally

You can build a Nuget package locally with `make-package.bat`
located in `devops`. This script expects VS2022 Community Edition
installed in the default location. If you have other edition of
Visual Studio, edit the file to use the correct path to the
`vcvarsall.bat` file.

Run `make-package.bat` from the repository root directory with a
package revision as the first argument. There is no provision to
manage build numbers from the command line and other tools should
be used for this.

## Sample Application

A Visual Studio project is included in this repository under
`sample-isa-lib-crypto` to test the Nuget package built by this
project. This application computes multi-hash and multi-buffer
SHA256 checksums for input arguments.

In order to build `sample-isa-lib-crypto.exe`, open Nuget Package
manager in the solution and install either the locally-built Nuget
package or the one from [nuget.org][].

[nuget.org]: https://www.nuget.org/packages/StoneSteps._isa-l_crypto_.VS2022.Static/
[nasm.us]: https://www.nasm.us/