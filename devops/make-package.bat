@echo off

setlocal

if "%~1" == "" (
  echo Package revision must be provided as the first argument
  goto :EOF
)

set PKG_REL=2.26

set PKG_VER=%PKG_REL%.0
set PKG_REV=%~1

set ISACRYPTO_FNAME=isa-l_crypto-%PKG_REL%.tar.gz
set ISACRYPTO_DNAME=isa-l_crypto-%PKG_REL%
set ISACRYPTO_SHA256=60f7f50637df86f39fe698653a4e3de41ed3e0953f5bff294f19572492c2ee19

set NASM_VER=2.16.03
set NASM_FNAME=nasm-%NASM_VER%-win64.zip
set NASM_DNAME=nasm-%NASM_VER%
set NASM_SHA256=3ee4782247bcb874378d02f7eab4e294a84d3d15f3f6ee2de2f47a46aa7226e6

set PATCH=%PROGRAMFILES%\Git\usr\bin\patch.exe
set SEVENZIP_EXE=%PROGRAMFILES%\7-Zip\7z.exe
set VCVARSALL=%PROGRAMFILES%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall

if NOT EXIST %ISACRYPTO_FNAME% (
  curl --location --remote-name https://github.com/intel/isa-l_crypto/archive/refs/tags/v%PKG_REL%.tar.gz
)

"%SEVENZIP_EXE%" h -scrcSHA256 %ISACRYPTO_FNAME% | findstr /C:"SHA256 for data" | call devops\check-sha256 "%ISACRYPTO_SHA256%"

if ERRORLEVEL 1 (
  echo SHA-256 signature for %ISACRYPTO_FNAME% does not match
  goto :EOF
)

if NOT EXIST %NASM_FNAME% (
  curl --location --remote-name https://www.nasm.us/pub/nasm/releasebuilds/%NASM_VER%/win64/%NASM_FNAME%
)

"%SEVENZIP_EXE%" h -scrcSHA256 %NASM_FNAME% | findstr /C:"SHA256 for data" | call devops\check-sha256 "%NASM_SHA256%"

if ERRORLEVEL 1 (
  echo SHA-256 signature for %NASM_FNAME% does not match
  goto :EOF
)

tar -xzf %ISACRYPTO_FNAME%

"%SEVENZIP_EXE%" x %NASM_FNAME%

cd %ISACRYPTO_DNAME%

call "%VCVARSALL%" x64

cmake -S . -B _build -A x64 ^
    -DCMAKE_ASM_NASM_COMPILER=%CD%\..\%NASM_DNAME%\nasm.exe ^
    -DBUILD_TESTS=OFF ^
    -DBUILD_PERF=OFF  ^
    -DBUILD_SHARED_LIBS=OFF

rem
rem x64 Debug
rem 
cmake --build _build --config Debug

rem `cmake --install` does not copy PDB files, so skip install and copy files from the build directories
mkdir ..\nuget\build\native\lib\x64\Debug
copy /Y _build\Debug\isal_crypto.pdb ..\nuget\build\native\lib\x64\Debug\
copy /Y _build\Debug\isal_crypto.lib ..\nuget\build\native\lib\x64\Debug\

cmake --build _build --config Debug --target clean

rem
rem x64 Release
rem 

cmake --build _build --config Release

cmake --install _build --config Release --prefix _install\Release

cmake --build _build --config Release --target clean

rem CMake does not generate PDB files for release builds, which is unfortunate
mkdir ..\nuget\build\native\lib\x64\Release
copy /Y _install\Release\lib\isal_crypto.lib ..\nuget\build\native\lib\x64\Release\

rem copy all header files and keep the directory structure
mkdir ..\nuget\build\native\include\isa-l_crypto
copy /Y _install\Release\include\* ..\nuget\build\native\include\
copy /Y _install\Release\include\isa-l_crypto\* ..\nuget\build\native\include\isa-l_crypto

rem
rem licenses
rem
mkdir ..\nuget\licenses
copy LICENSE ..\nuget\licenses\

cd ..

rem
rem Create a package
rem
nuget pack nuget\StoneSteps.IsaLibCrypto.VS2022.Static.nuspec -Version %PKG_VER%.%PKG_REV%
