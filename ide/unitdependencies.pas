{
/***************************************************************************
                             unitdependencies.pas
                             --------------------

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
 
 
  Author: Mattias Gaertner
 
  Abstract:
    Defines the TUnitDependenciesView form.
    The Unit Dependencies shows the used units in a treeview.
 
}
unit UnitDependencies;

{$mode objfpc}{$H+}

interface

{$I ide.inc}

uses
  {$IFDEF IDE_MEM_CHECK}
  MemCheck,
  {$ENDIF}
  Classes, SysUtils, Controls, Forms, Dialogs, Buttons, ComCtrls, StdCtrls,
  CodeToolManager, CodeCache, EnvironmentOpts, LResources, IDEOptionDefs,
  LazarusIDEStrConsts, InputHistory, IDEProcs, Graphics;
  
type

  { TUnitNode }
  
  TUnitNodeFlag = (
    unfImplementation, // this unit was used in an implementation uses section
    unfCircle,         // this unit is the parent of itself
    unfForbiddenCircle,// forbidden circle
    unfFileNotFound,   // this unit file was not found
    unfParseError      // error parsing the source
    );
  TUnitNodeFlags = set of TUnitNodeFlag;
  
  TUnitNodeSourceType = (
    unstUnknown,
    unstUnit,
    unstProgram,
    unstLibrary,
    unstPackage
    );
    
const
  UnitNodeSourceTypeNames: array[TUnitNodeSourceType] of string = (
    '?',
    'Unit',
    'Program',
    'Library',
    'Package'
    );

type
  TUnitNode = class
  private
    FChildCount: integer;
    FCodeBuffer: TCodeBuffer;
    FFilename: string;
    FFirstChild: TUnitNode;
    FFlags: TUnitNodeFlags;
    FLastChild: TUnitNode;
    FNextSibling: TUnitNode;
    FParent: TUnitNode;
    FPrevSibling: TUnitNode;
    FShortFilename: string;
    FSourceType: TUnitNodeSourceType;
    FTreeNode: TTreeNode;
    procedure SetCodeBuffer(const AValue: TCodeBuffer);
    procedure SetFilename(const AValue: string);
    procedure SetParent(const AValue: TUnitNode);
    procedure SetShortFilename(const AValue: string);
    procedure SetTreeNode(const AValue: TTreeNode);
    procedure CreateShortFilename;
    procedure UnbindFromParent;
    procedure AddToParent;
    procedure AddChild(const AFilename: string; ACodeBuffer: TCodeBuffer;
      InImplementation: boolean);
    procedure UpdateSourceType;
    function ForbiddenCircle: boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ClearChilds;
    procedure CreateChilds;
    procedure ClearGrandChildren;
    procedure CreateGrandChildren;
    function FindParentWithCodeBuffer(ACodeBuffer: TCodeBuffer): TUnitNode;
    function HasChildren: boolean;
    function ImageIndex: integer;
    function IsImplementationNode: boolean;
    function StateImageIndex: integer;
    property ChildCount: integer read FChildCount;
    property CodeBuffer: TCodeBuffer read FCodeBuffer write SetCodeBuffer;
    property Filename: string read FFilename write SetFilename;
    property FirstChild: TUnitNode read FFirstChild;
    property Flags: TUnitNodeFlags read FFlags;
    property LastChild: TUnitNode read FLastChild;
    property NextSibling: TUnitNode read FNextSibling;
    property PrevSibling: TUnitNode read FPrevSibling;
    property Parent: TUnitNode read FParent write SetParent;
    property ShortFilename: string read FShortFilename write SetShortFilename;
    property SourceType: TUnitNodeSourceType read FSourceType;
    property TreeNode: TTreeNode read FTreeNode write SetTreeNode;
  end;


  { TUnitDependenciesView }

  TUnitDependenciesView = class(TForm)
    SrcTypeImageList: TImageList;
    FlagImageList: TImageList;
    UnitHistoryList: TComboBox;
    SelectUnitButton: TBitBtn;
    UnitTreeView: TTreeView;
    RefreshButton: TBitBtn;
    procedure UnitDependenciesViewResize(Sender: TObject);
    procedure UnitTreeViewCollapsing(Sender: TObject; Node: TTreeNode;
          var AllowCollapse: Boolean);
    procedure UnitTreeViewExpanding(Sender: TObject; Node: TTreeNode;
          var AllowExpansion: Boolean);
  private
    FRootCodeBuffer: TCodeBuffer;
    FRootFilename: string;
    FRootNode: TUnitNode;
    FRootShortFilename: string;
    FRootValid: boolean;
    procedure DoResize;
    procedure ClearTree;
    procedure RebuildTree;
    procedure SetRootFilename(const AValue: string);
    procedure SetRootShortFilename(const AValue: string);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    function RootValid: boolean;
    procedure UpdateUnitTree;
    property RootFilename: string read FRootFilename write SetRootFilename;
    property RootShortFilename: string read FRootShortFilename write SetRootShortFilename;
  end;
  
const
  UnitDependenciesView: TUnitDependenciesView = nil;

implementation


{ TUnitDependenciesView }

procedure TUnitDependenciesView.UnitDependenciesViewResize(Sender: TObject);
begin
  DoResize;
end;

procedure TUnitDependenciesView.UnitTreeViewCollapsing(Sender: TObject;
  Node: TTreeNode; var AllowCollapse: Boolean);
var
  UnitNode: TUnitNode;
begin
  AllowCollapse:=true;
  UnitNode:=TUnitNode(Node.Data);
  UnitNode.ClearGrandChildren;
end;

procedure TUnitDependenciesView.UnitTreeViewExpanding(Sender: TObject;
  Node: TTreeNode; var AllowExpansion: Boolean);
var
  UnitNode: TUnitNode;
begin
  UnitNode:=TUnitNode(Node.Data);
  if UnitNode.HasChildren then begin
    AllowExpansion:=true;
    UnitNode.CreateGrandChildren;
  end else begin
    AllowExpansion:=false;
  end;
end;

procedure TUnitDependenciesView.DoResize;
begin
  with UnitHistoryList do begin
    SetBounds(0,0,Parent.ClientWidth-Left,Height);
  end;

  with SelectUnitButton do begin
    SetBounds(0,UnitHistoryList.Top+UnitHistoryList.Height+2,25,Height);
  end;

  with RefreshButton do begin
    SetBounds(SelectUnitButton.Left+SelectUnitButton.Width+5,
              SelectUnitButton.Top,100,SelectUnitButton.Height);
  end;

  with UnitTreeView do begin
    SetBounds(0,SelectUnitButton.Top+SelectUnitButton.Height+2,
              Parent.ClientWidth,Parent.ClientHeight-Top);
  end;
end;

procedure TUnitDependenciesView.ClearTree;
begin
  FRootNode.Free;
  FRootNode:=nil;
end;

procedure TUnitDependenciesView.RebuildTree;
begin
  ClearTree;
  if RootFilename='' then exit;
  FRootNode:=TUnitNode.Create;
  FRootNode.CodeBuffer:=FRootCodeBuffer;
  FRootNode.Filename:=RootFilename;
  FRootNode.ShortFilename:=FRootShortFilename;
  UnitTreeView.Items.Clear;
  FRootNode.TreeNode:=UnitTreeView.Items.Add(nil,'');
  FRootNode.CreateChilds;
end;

procedure TUnitDependenciesView.SetRootFilename(const AValue: string);
begin
  if FRootFilename=AValue then exit;
  FRootFilename:=AValue;
  FRootCodeBuffer:=CodeToolBoss.FindFile(FRootFilename);
  FRootShortFilename:=FRootFilename;
  RebuildTree;
  UpdateUnitTree;
end;

procedure TUnitDependenciesView.SetRootShortFilename(const AValue: string);
begin
  if FRootShortFilename=AValue then exit;
  FRootShortFilename:=AValue;
  if FRootNode<>nil then
    FRootNode.ShortFilename:=AValue;
end;

function TUnitDependenciesView.RootValid: boolean;
begin
  Result:=FRootValid;
end;

procedure TUnitDependenciesView.UpdateUnitTree;
begin

end;

constructor TUnitDependenciesView.Create(TheOwner: TComponent);

  procedure AddResImg(ImgList: TImageList; const ResName: string);
  var Pixmap: TPixmap;
  begin
    Pixmap:=TPixmap.Create;
    Pixmap.TransparentColor:=clWhite;
    Pixmap.LoadFromLazarusResource(ResName);
    ImgList.Add(Pixmap,nil)
  end;

var
  ALayout: TIDEWindowLayout;
begin
  inherited Create(TheOwner);
  if LazarusResources.Find(ClassName)=nil then begin
    Name:=DefaultUnitDependenciesName;
    Caption := 'Unit Dependencies';
    ALayout:=EnvironmentOptions.IDEWindowLayoutList.ItemByFormID(Name);
    ALayout.Form:=TForm(Self);
    ALayout.Apply;
    
    SrcTypeImageList:=TImageList.Create(Self);
    with SrcTypeImageList do begin
      Name:='SrcTypeImageList';
      Width:=22;
      Height:=22;
      AddResImg(SrcTypeImageList,'srctype_unknown_22x22');
      AddResImg(SrcTypeImageList,'srctype_unit_22x22');
      AddResImg(SrcTypeImageList,'srctype_program_22x22');
      AddResImg(SrcTypeImageList,'srctype_library_22x22');
      AddResImg(SrcTypeImageList,'srctype_package_22x22');
      AddResImg(SrcTypeImageList,'srctype_filenotfound_22x22');
      AddResImg(SrcTypeImageList,'srctype_parseerror_22x22');
    end;

    FlagImageList:=TImageList.Create(Self);
    with FlagImageList do begin
      Name:='FlagImageList';
      Width:=22;
      Height:=22;
      AddResImg(SrcTypeImageList,'interface_unit_22x22.xpm');
      AddResImg(SrcTypeImageList,'implementation_unit_22x22.xpm');
      AddResImg(SrcTypeImageList,'forbidden_unit_circle_22x22.xpm');
      AddResImg(SrcTypeImageList,'allowed_unit_circle_22x22.xpm');
    end;
    
    UnitHistoryList:=TComboBox.Create(Self);
    with UnitHistoryList do begin
      Name:='UnitHistoryList';
      Parent:=Self;
      Left:=0;
      Top:=0;
      Width:=Parent.ClientWidth-Left;
      Enabled:=false;
      Visible:=true;
    end;
    
    SelectUnitButton:=TBitBtn.Create(Self);
    with SelectUnitButton do begin
      Name:='SelectUnitButton';
      Parent:=Self;
      Left:=0;
      Top:=UnitHistoryList.Top+UnitHistoryList.Height+2;
      Width:=25;
      Caption:='...';
      Enabled:=false;
      Visible:=true;
    end;
    
    RefreshButton:=TBitBtn.Create(Self);
    with RefreshButton do begin
      Name:='RefreshButton';
      Parent:=Self;
      Left:=SelectUnitButton.Left+SelectUnitButton.Width+5;
      Top:=SelectUnitButton.Top;
      Width:=100;
      Height:=SelectUnitButton.Height;
      Caption:='Refresh';
      Enabled:=false;
      Visible:=true;
    end;

    UnitTreeView:=TTreeView.Create(Self);
    with UnitTreeView do begin
      Name:='UnitTreeView';
      Parent:=Self;
      Left:=0;
      Top:=SelectUnitButton.Top+SelectUnitButton.Height+2;
      Width:=Parent.ClientWidth;
      Height:=Parent.ClientHeight-Top;
      OnExpanding:=@UnitTreeViewExpanding;
      OnCollapsing:=@UnitTreeViewCollapsing;
      Images:=SrcTypeImageList;
      StateImages:=FlagImageList;
      Visible:=true;
    end;
    
    OnResize:=@UnitDependenciesViewResize;
  end;
end;

destructor TUnitDependenciesView.Destroy;
begin
  ClearTree;
  inherited Destroy;
end;

{ TUnitNode }

procedure TUnitNode.SetCodeBuffer(const AValue: TCodeBuffer);
begin
  if CodeBuffer=AValue then exit;
  FCodeBuffer:=AValue;
  if CodeBuffer<>nil then
    Filename:=CodeBuffer.Filename;
end;

procedure TUnitNode.SetFilename(const AValue: string);
begin
  if Filename=AValue then exit;
  FFilename:=AValue;
  FSourceType:=unstUnknown;
  CreateShortFilename;
end;

procedure TUnitNode.SetParent(const AValue: TUnitNode);
begin
  if Parent=AValue then exit;
  UnbindFromParent;
  FParent:=AValue;
  if Parent<>nil then AddToParent;
end;

procedure TUnitNode.SetShortFilename(const AValue: string);
begin
  if ShortFilename=AValue then exit;
  FShortFilename:=AValue;
  if TreeNode<>nil then
    TreeNode.Text:=FShortFilename;
end;

procedure TUnitNode.SetTreeNode(const AValue: TTreeNode);
begin
  if TreeNode=AValue then exit;
  FTreeNode:=AValue;
  if TreeNode<>nil then begin
    TreeNode.Text:=ShortFilename;
    TreeNode.Data:=Self;
    TreeNode.HasChildren:=HasChildren;
    TreeNode.ImageIndex:=ImageIndex;
    TreeNode.StateIndex:=StateImageIndex;
  end;
end;

procedure TUnitNode.CreateShortFilename;
begin
  ShortFilename:=Filename;
  if (Parent<>nil) and (FilenameIsAbsolute(Parent.Filename))
  and (FilenameIsAbsolute(Filename)) then begin
    ShortFilename:=ExtractRelativePath(ExtractFilePath(Parent.Filename),
                                       Filename);
  end;
end;

procedure TUnitNode.UnbindFromParent;
begin
  if TreeNode<>nil then begin
    TreeNode.Free;
    TreeNode:=nil;
  end;
  if Parent<>nil then begin
    if Parent.FirstChild=Self then Parent.FFirstChild:=NextSibling;
    if Parent.LastChild=Self then Parent.FLastChild:=PrevSibling;
    Dec(Parent.FChildCount);
  end;
  if NextSibling<>nil then NextSibling.FPrevSibling:=PrevSibling;
  if PrevSibling<>nil then PrevSibling.FNextSibling:=NextSibling;
  FNextSibling:=nil;
  FPrevSibling:=nil;
  FParent:=nil;
end;

procedure TUnitNode.AddToParent;
begin
  if Parent=nil then exit;
  
  FPrevSibling:=Parent.LastChild;
  FNextSibling:=nil;
  Parent.FLastChild:=Self;
  if Parent.FirstChild=nil then Parent.FFirstChild:=Self;
  if PrevSibling<>nil then PrevSibling.FNextSibling:=Self;
  Inc(Parent.FChildCount);
  CreateShortFilename;
  
  if Parent.TreeNode<>nil then begin
    Parent.TreeNode.HasChildren:=true;
    TreeNode:=Parent.TreeNode.TreeNodes.AddChild(Parent.TreeNode,'');
    if Parent.TreeNode.Expanded then begin
      CreateChilds;
    end;
  end;
end;

procedure TUnitNode.AddChild(const AFilename: string; ACodeBuffer: TCodeBuffer;
  InImplementation: boolean);
var
  NewNode: TUnitNode;
begin
  NewNode:=TUnitNode.Create;
  NewNode.CodeBuffer:=ACodeBuffer;
  NewNode.Filename:=AFilename;
  if ACodeBuffer<>nil then begin
    if FindParentWithCodeBuffer(ACodeBuffer)<>nil then begin
      Include(NewNode.FFlags,unfCircle);
      if ForbiddenCircle then
        Include(NewNode.FFlags,unfForbiddenCircle);
    end;
  end else begin
    Include(NewNode.FFlags,unfFileNotFound);
  end;
  if InImplementation then
    Include(NewNode.FFlags,unfImplementation);
  NewNode.Parent:=Self;
end;

procedure TUnitNode.UpdateSourceType;
var
  SourceKeyWord: string;
  ASrcType: TUnitNodeSourceType;
begin
  FSourceType:=unstUnknown;
  if CodeBuffer=nil then exit;
  SourceKeyWord:=CodeToolBoss.GetSourceType(CodeBuffer,false);
  for ASrcType:=Low(TUnitNodeSourceType) to High(TUnitNodeSourceType) do
    if AnsiCompareText(SourceKeyWord,UnitNodeSourceTypeNames[ASrcType])=0
    then
      FSourceType:=ASrcType;
  if TreeNode<>nil then begin
    TreeNode.ImageIndex:=ImageIndex;
    TreeNode.StateIndex:=StateImageIndex;
  end;
end;

function TUnitNode.ForbiddenCircle: boolean;
var
  ParentNode, CurNode: TUnitNode;
begin
  CurNode:=Self;
  ParentNode:=Parent;
  while ParentNode<>nil do begin
    if ParentNode.CodeBuffer=CodeBuffer then begin
      // circle detected
      if unfImplementation in CurNode.Flags then begin
        Result:=true;
        exit;
      end;
    end;
    CurNode:=ParentNode;
    ParentNode:=ParentNode.Parent;
  end;
end;

constructor TUnitNode.Create;
begin
  inherited Create;
  FSourceType:=unstUnknown;
end;

destructor TUnitNode.Destroy;
begin
  ClearChilds;
  Parent:=nil;
  inherited Destroy;
end;

procedure TUnitNode.ClearChilds;
begin
  while LastChild<>nil do
    LastChild.Free;
end;

procedure TUnitNode.CreateChilds;
var
  UsedInterfaceFilenames, UsedImplementationFilenames: TStrings;
  i: integer;
begin
  ClearChilds;
  UpdateSourceType;
  if CodeBuffer=nil then exit;
  if CodeToolBoss.FindUsedUnits(CodeBuffer,
                                UsedInterfaceFilenames,
                                UsedImplementationFilenames) then
  begin
    Exclude(FFlags,unfParseError);
    for i:=0 to UsedInterfaceFilenames.Count-1 do
      AddChild(UsedInterfaceFilenames[i],
               TCodeBuffer(UsedInterfaceFilenames.Objects[i]),false);
    UsedInterfaceFilenames.Free;
    for i:=0 to UsedImplementationFilenames.Count-1 do
      AddChild(UsedImplementationFilenames[i],
               TCodeBuffer(UsedImplementationFilenames.Objects[i]),true);
    UsedImplementationFilenames.Free;
  end else begin
    Include(FFlags,unfParseError);
  end;
end;

procedure TUnitNode.ClearGrandChildren;
var
  AChildNode: TUnitNode;
begin
  AChildNode:=FirstChild;
  while AChildNode<>nil do begin
    AChildNode.ClearChilds;
    AChildNode:=AChildNode.NextSibling;
  end;
end;

procedure TUnitNode.CreateGrandChildren;
var
  AChildNode: TUnitNode;
begin
  AChildNode:=FirstChild;
  while AChildNode<>nil do begin
    AChildNode.CreateChilds;
    AChildNode:=AChildNode.NextSibling;
  end;
end;

function TUnitNode.FindParentWithCodeBuffer(ACodeBuffer: TCodeBuffer
  ): TUnitNode;
begin
  Result:=Parent;
  while (Result<>nil) and (Result.CodeBuffer<>ACodeBuffer) do
    Result:=Result.Parent;
end;

function TUnitNode.HasChildren: boolean;
begin
  Result:=FChildCount>0;
end;

function TUnitNode.ImageIndex: integer;
begin
  case SourceType of
  unstUnit:    Result:=1;
  unstProgram: Result:=2;
  unstLibrary: Result:=3;
  unstPackage: Result:=4;
  else
    begin
      if unfFileNotFound in Flags then
        Result:=5
      else if unfParseError in Flags then
        Result:=6
      else
        Result:=0;
    end;
  end;
end;

function TUnitNode.IsImplementationNode: boolean;
begin
  Result:=unfImplementation in FFlags;
end;

function TUnitNode.StateImageIndex: integer;
begin
  if not (unfCircle in Flags) then begin
    if not (unfImplementation in Flags) then begin
      Result:=0; // normal used unit
    end else begin
      Result:=1; // unit used in implementation section
    end;
  end else begin
    if not (unfForbiddenCircle in Flags) then begin
      Result:=2; // allowed unit circle
    end else begin
      Result:=3; // forbidden unit circle
    end;
  end;
end;

//-----------------------------------------------------------------------------
initialization
  {$I unitdependencies.lrs}

end.

