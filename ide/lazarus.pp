{
 /***************************************************************************
                                 Lazarus.pp
                             -------------------
                   This is the lazarus editor program.

                   Initial Revision  : Sun Mar 28 23:15:32 CST 1999


 ***************************************************************************/

 ***************************************************************************
 *                                                                         *
 *   This source is free software; you can redistribute it and/or modify   *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This code is distributed in the hope that it will be useful, but      *
 *   WITHOUT ANY WARRANTY; without even the implied warranty of            *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
 *   General Public License for more details.                              *
 *                                                                         *
 *   A copy of the GNU General Public License is available on the World    *
 *   Wide Web at <http://www.gnu.org/copyleft/gpl.html>. You can also      *
 *   obtain it by writing to the Free Software Foundation,                 *
 *   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.        *
 *                                                                         *
 ***************************************************************************
}

program Lazarus;

{$mode objfpc}{$H+}

{$I ide.inc}

{off $DEFINE IDE_MEM_CHECK}

uses
  {$IFDEF HEAPTRC_WINDOW}
  redirect_stderr,
  {$ENDIF HEAPTRC_WINDOW}
  {$IF defined(UNIX) and not defined(DisableMultiThreading)}
  cthreads,
  {$ENDIF}
  {$IFDEF IDE_MEM_CHECK}
  MemCheck,
  {$ENDIF}
  {$IF defined(Unix)}
  clocale,
  {$IFEND}
  SysUtils,
  Interfaces,
  Forms, LCLProc,
  LazConf, IDEGuiCmdLine,
  Splash,
  Main,
  AboutFrm,
  // use the custom IDE static packages AFTER 'main'
  {$IFDEF AddStaticPkgs}
  {$I staticpackages.inc}
  {$ENDIF}
  {$IFDEF BigIDE}
    allsyneditdsgn, RunTimeTypeInfoControls, Printer4Lazarus, Printers4LazIDE,
    LeakView, MemDSLaz, SDFLaz, InstantFPCLaz, ExternHelp,
    TurboPowerIPro, {$ifdef UseTurbopowerInHelp}TurboPowerIProDsgn,{$endif}
    jcfidelazarus, chmhelppkg,
    FPCUnitTestRunner, FPCUnitIDE, ProjTemplates, TAChartLazarusPkg,
    TodoListLaz,
    SQLDBLaz, DBFLaz,
  {$ENDIF}
  MainBase;

{$I revision.inc}
{$R lazarus.res}

begin
  {$IFDEF IDE_MEM_CHECK}CheckHeapWrtMemCnt('lazarus.pp: begin');{$ENDIF}

  RequireDerivedFormResource := True;

  // When quick rebuilding the IDE (e.g. when the set of install packages have
  // changed), only the unit paths have changed and so FPC rebuilds only the
  // lazarus.pp.
  // Any flag that should work with quick build must be set here.
  KeepInstalledPackages:={$IF defined(BigIDE) or defined(KeepInstalledPackages)}True{$ELSE}False{$ENDIF};

  // end of build flags
  
  LazarusRevisionStr:=RevisionStr;
  Application.Title:='Lazarus';
  OnGetApplicationName:=@GetLazarusApplicationName;
  Application.Initialize;
  TMainIDE.ParseCmdLineOptions;
  if not SetupMainIDEInstance then exit;
  if Application.Terminated then exit;

  // Show splashform
  if ShowSplashScreen then begin
    SplashForm := TSplashForm.Create(nil);
    SplashForm.Show;
    Application.ProcessMessages; // process splash paint message
  end;

  TMainIDE.Create(Application);
  if not Application.Terminated then
  begin
    MainIDE.CreateOftenUsedForms;
    try
      MainIDE.StartIDE;
    except
      Application.HandleException(MainIDE);
    end;
    {$IFDEF IDE_MEM_CHECK}CheckHeapWrtMemCnt('lazarus.pp: TMainIDE created');{$ENDIF}

    try
      Application.Run;
    except
      debugln('lazarus.pp - unhandled exception');
      CleanUpPIDFile;
      Halt;
    end;
  end;
  CleanUpPIDFile;
  FreeThenNil(SplashForm);

  debugln('LAZARUS END - cleaning up ...');

  // free the IDE, so everything is freed before the finalization sections
  MainIDE.Free;
end.

