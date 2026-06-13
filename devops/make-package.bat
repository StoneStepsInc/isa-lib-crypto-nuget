@echo off

setlocal

if "%~1" == "" (
  echo Package revision must be provided as the first argument
  goto :EOF
)

set PKG_REL=2.26.1

rem add `.0` for missing dot-zero releases, like 2.26
set PKG_VER=%PKG_REL%
set PKG_REV=%~1

set ISACRYPTO_FNAME=isa-l_crypto-%PKG_REL%.tar.gz
set ISACRYPTO_DNAME=isa-l_crypto-%PKG_REL%
set ISACRYPTO_SHA256=dd83e3da8e589d15ff475ac727b38c8cba48d2e82465fa58de2b5d9fefcd682b

set NASM_VER=3.01
set NASM_FNAME=nasm-%NASM_VER%-win64.zip
set NASM_DNAME=nasm-%NASM_VER%
set NASM_SHA256=e0ba5157007abc7b1a65118a96657a961ddf55f7e3f632ee035366dfce039ca4

set PATCH=%PROGRAMFILES%\Git\usr\bin\patch.exe
set SEVENZIP_EXE=%PROGRAMFILES%\7-Zip\7z.exe
set VCVARSALL=%PROGRAMFILES%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall

if NOT EXIST %ISACRYPTO_FNAME% (
  curl --location --output %ISACRYPTO_FNAME% https://github.com/intel/isa-l_crypto/archive/refs/tags/v%PKG_REL%.tar.gz
)

"%SEVENZIP_EXE%" h -scrcSHA256 %ISACRYPTO_FNAME% | findstr /C:"SHA256 for data" | call devops\check-sha256 "%ISACRYPTO_SHA256%"

if ERRORLEVEL 1 (
  echo SHA-256 signature for %ISACRYPTO_FNAME% does not match
  goto :EOF
)

if NOT EXIST %NASM_FNAME% (
  curl --location --output %NASM_FNAME% https://www.nasm.us/pub/nasm/releasebuilds/%NASM_VER%/win64/%NASM_FNAME%
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

cmake -S . -B _build -A x64 -G "Visual Studio 17 2022" ^
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
copy /Y _build\Debug\isa-l_crypto.pdb ..\nuget\build\native\lib\x64\Debug\
copy /Y _build\Debug\isa-l_crypto.lib ..\nuget\build\native\lib\x64\Debug\

cmake --build _build --config Debug --target clean

rem
rem x64 Release
rem 

cmake --build _build --config RelWithDebInfo

cmake --install _build --config RelWithDebInfo --prefix _install\Release

mkdir ..\nuget\build\native\lib\x64\Release
copy /Y _build\RelWithDebInfo\isa-l_crypto.pdb ..\nuget\build\native\lib\x64\Release\
copy /Y _build\RelWithDebInfo\isa-l_crypto.lib ..\nuget\build\native\lib\x64\Release\

cmake --build _build --config RelWithDebInfo --target clean

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
