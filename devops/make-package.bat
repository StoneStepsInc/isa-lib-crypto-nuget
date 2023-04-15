@echo off

setlocal

if "%~1" == "" (
  echo Package revision must be provided as the first argument
  goto :EOF
)

set PKG_VER=2.24.0
set PKG_REV=%~1

set ISACRYPTO_FNAME=isa-l_crypto-%PKG_VER%.tar.gz
set ISACRYPTO_DNAME=isa-l_crypto-%PKG_VER%
set ISACRYPTO_SHA256=1b2d5623f75c94562222a00187c7a9de010266ab7f76e86b553b68bb654d39be

set NASM_VER=2.16.01
set NASM_FNAME=nasm-%NASM_VER%-win64.zip
set NASM_DNAME=nasm-%NASM_VER%
set NASM_SHA256=029eed31faf0d2c5f95783294432cbea6c15bf633430f254bb3c1f195c67ca3a

set PATCH=c:\Program Files\Git\usr\bin\patch.exe
set SEVENZIP_EXE=c:\Program Files\7-Zip\7z.exe
set VCVARSALL=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall

curl --location --output %ISACRYPTO_FNAME% https://github.com/intel/isa-l_crypto/archive/refs/tags/v%PKG_VER%.tar.gz
                                       
"%SEVENZIP_EXE%" h -scrcSHA256 %ISACRYPTO_FNAME% | findstr /C:"SHA256 for data" | call devops\check-sha256 "%ISACRYPTO_SHA256%"

if ERRORLEVEL 1 (
  echo SHA-256 signature for %ISACRYPTO_FNAME% does not match
  goto :EOF
)

curl --location --output %NASM_FNAME% https://www.nasm.us/pub/nasm/releasebuilds/%NASM_VER%/win64/%NASM_FNAME%

"%SEVENZIP_EXE%" h -scrcSHA256 %NASM_FNAME% | findstr /C:"SHA256 for data" | call devops\check-sha256 "%NASM_SHA256%"

if ERRORLEVEL 1 (
  echo SHA-256 signature for %NASM_FNAME% does not match
  goto :EOF
)

tar -xzf %ISACRYPTO_FNAME%

"%SEVENZIP_EXE%" x %NASM_FNAME%

cd %ISACRYPTO_DNAME%

rem apply a patch to allow building debug/release configurations
"%PATCH%" -p1 --unified --input ..\patches\01-nmake-debug-release.patch

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
