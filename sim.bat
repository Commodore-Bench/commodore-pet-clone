@echo off
setlocal EnableDelayedExpansion

set PROJDIR=%~dp0\rtl\t8\PET
set BINDIR=C:\Efinity\2022.2\bin

:Parse
    if /I "%~1" == "--run" goto Run

:Update
    :: Move to the root of the Efinity project so that 'efx_run' artifacts are generated
    :: within the \work_sim\ subdirectory.
    pushd %PROJDIR%

    :: Invoke 'efx_run' to generate/update the '\work_sim\<proj>.f' file, but ignore
    :: the resulting Python exception which occures due to lack of SystemVerilog support.
    :: 
    :: (See https://www.efinixinc.com/support/forum.php?cid=6&pid=932)
    cmd /c %BINDIR%\efx_run PET.xml --flow rtlsim 2> NUL
    popd
    echo.

:Run
    :: 'efx_run' produces relative paths to simulation files.  Therefore, we must execute
    :: iverilog from the root of the project directory.
    pushd %PROJDIR%

    iverilog.exe -g2009 -s sim -o%PROJDIR%\work_sim\PET.vvp -f%PROJDIR%\work_sim\PET.f
    vvp.exe -l%PROJDIR%\outflow\PET.rtl.simlog %PROJDIR%\work_sim\PET.vvp
    popd && exit /b %ERRORLEVEL%