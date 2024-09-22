@echo off

setlocal

if "%~1" == "" (
  echo Package revision must be provided as the first argument
  goto :EOF
)

set PKG_VER=2.25.0
set PKG_REV=%~1

set ISACRYPTO_FNAME=isa-l_crypto-%PKG_VER%.tar.gz
set ISACRYPTO_DNAME=isa-l_crypto-%PKG_VER%
set ISACRYPTO_SHA256=afe013e8eca17c9a0e567709c6a967f6b2b497d5317914afc98d5969599ee87e

set NASM_VER=2.16.03
set NASM_FNAME=nasm-%NASM_VER%-win64.zip
set NASM_DNAME=nasm-%NASM_VER%
set NASM_SHA256=3ee4782247bcb874378d02f7eab4e294a84d3d15f3f6ee2de2f47a46aa7226e6

set PATCH=%PROGRAMFILES%\Git\usr\bin\patch.exe
set SEVENZIP_EXE=%PROGRAMFILES%\7-Zip\7z.exe
set VCVARSALL=%PROGRAMFILES%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall

if NOT EXIST %ISACRYPTO_FNAME% (
  curl --location --output %ISACRYPTO_FNAME% https://github.com/intel/isa-l_crypto/archive/refs/tags/v%PKG_VER%.tar.gz
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

rem apply a patch to allow building debug/release configurations
"%PATCH%" -p 1 --unified --input ..\patches\01-nmake-debug-release.patch

if ERRORLEVEL 1 (
  echo Cannot apply patch 01-nmake-debug-release.patch
  goto :EOF
)

call "%VCVARSALL%" x64

rem nmake will find nasm.exe in the current directory
copy /Y ..\%NASM_DNAME%\nasm.exe .

rem
rem Build x64 Debug
rem 
nmake -f Makefile.nmake static CONFIG=DEBUG

mkdir ..\nuget\build\native\lib\x64\Debug
copy /Y isa-l_crypto_static.lib ..\nuget\build\native\lib\x64\Debug\

rem
rem Clean up
rem

nmake -f Makefile.nmake clean

rem nmake clean deletes all executables, including nasm.exe
copy /Y ..\%NASM_DNAME%\nasm.exe .

rem
rem Build x64 Release
rem 

nmake -f Makefile.nmake static CONFIG=RELEASE

mkdir ..\nuget\build\native\lib\x64\Release
copy /Y isa-l_crypto_static.lib ..\nuget\build\native\lib\x64\Release\

rem
rem Headers and licenses
rem
mkdir ..\nuget\licenses
copy LICENSE ..\nuget\licenses\

mkdir ..\nuget\build\native\include\
copy /Y include\* ..\nuget\build\native\include\

cd ..

rem
rem Create a package
rem
nuget pack nuget\StoneSteps.IsaLibCrypto.VS2022.Static.nuspec -Version %PKG_VER%.%PKG_REV%
