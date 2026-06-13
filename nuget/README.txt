This package contains static isa-l_crypto libraries and header
files for the x64 platform built with Visual C++ 2022, against
Debug/Release MT/DLL MSVC CRT, using the following build options.

--   Shared libraries:     OFF
--   Build tests:          OFF
--   Build perf apps:      OFF
--   Safe data:            ON
--   Safe param:           ON
--   FIPS mode:            OFF

The isa-l_crypto static libraries from this package will appear
within the installation target project after the package is
installed. The solution may need to be reloaded to make libraries
visible. Both, debug and release libraries will be listed in the
project, but only the one appropriate for the currently selected
configuration will be included in the build. These libraries
may be moved into solution folders after the installation (e.g.
lib/Debug and lib/Release).

Note that the isa-l_crypto library path in this package will
be selected as Debug or Release based on whether the selected
configuration is designated as a development or as a release
configuration via the standard Visual Studio property called
UseDebugLibraries. Additional configurations copied from the
standard ones will inherit this property. 

Do not install this package if your projects use debug
configurations without UseDebugLibraries. Note that CMake-generated
Visual Studio projects will not emit this property.

See README.md in isa-l-crypto-nuget project for more details.

https://github.com/StoneStepsInc/isa-l-crypto-nuget

WARNING: Due to changes in the build system in the upstream
project, the names of the static libraries and the locations of
the header files have changed. The new library file names are
isa-l_crypto.lib for all configurations. If upgrading from
v2.26.0, the original files named isal_crypto_static.lib
will be removed from Visual Studio projects on upgrade, but
you will need to place the new files into the solution folders
where isal_crypto_static.lib used to be manually.

WARNING: The upstream project introduced breaking changes in
v2.25.0 and the source compiled against v2.24.0 will not compile
against v2.25.0 and newer. See this page for details:

https://github.com/intel/isa-l_crypto/wiki/New-API-introduced-from-v2.25

