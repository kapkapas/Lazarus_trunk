{
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
    This unit is part of the IDE's help system. It implements the help for
    sources via fpdoc files and pascal comments.
}
unit CodeHelp;

{$mode objfpc}{$H+}

{off $DEFINE VerboseLazDoc}
{off $DEFINE VerboseLazDocFails}
{off $DEFINE VerboseHints}

{$IFDEF VerboseLazDoc}
  {$DEFINE VerboseLazDocFails}
{$ENDIF}

interface

uses
  Classes, SysUtils, LCLProc, Forms, Controls, FileUtil, Dialogs, AvgLvlTree,
  // codetools
  CodeAtom, CodeTree, CodeToolManager, FindDeclarationTool, BasicCodeTools,
  KeywordFuncLists, PascalParserTool, CodeCache, CacheCodeTools, FileProcs,
  {$IFDEF NewXMLCfg}
  Laz2_DOM, Laz2_XMLRead, Laz2_XMLWrite,
  {$ELSE}
  Laz_DOM, Laz_XMLRead, Laz_XMLWrite,
  {$ENDIF}
  // synedit
  SynHighlighterPas,
  // IDEIntf
  IDEMsgIntf, MacroIntf, PackageIntf, LazHelpIntf, ProjectIntf, IDEDialogs,
  IDEHelpIntf, LazIDEIntf,
  // IDE
  LazarusIDEStrConsts, CompilerOptions, IDEProcs, PackageDefs, EnvironmentOpts,
  TransferMacros, PackageSystem, DialogProcs;

const
  IDEProjectName = 'Lazarus';
type
  TFPDocItem = (
    fpdiShort,
    fpdiElementLink,
    fpdiDescription,
    fpdiErrors,
    fpdiSeeAlso,
    fpdiExample
    );

  TFPDocElementValues = array [TFPDocItem] of String;
  
const
  FPDocItemNames: array[TFPDocItem] of shortstring = (
      'short',
      'elementlink',
      'descr',
      'errors',
      'seealso',
      'example'
    );

type
  TLazFPDocFileFlag = (
    ldffDocChangingCalled,
    ldffDocChangedNeedsCalling
    );
  TLazFPDocFileFlags = set of TLazFPDocFileFlag;

  { TLazFPDocFile
    An fpdoc xml file. The CodeBuffer is the xml source. The Doc is the parsed dom tree. }

  TLazFPDocFile = class
  private
    fUpdateLock: integer;
    FFlags: TLazFPDocFileFlags;
  public
    Filename: string;// the fpdoc xml filename
    Doc: TXMLdocument;// IMPORTANT: if you change this, call DocChanging and DocChanged to notify the references
    DocErrorMsg: string; // if xml is broken, Doc could not be created
    DocModified: boolean;
    CodeBufferChangeStep: integer;// the CodeBuffer.ChangeStep value, when Doc was built
    CodeBuffer: TCodeBuffer;
    destructor Destroy; override;
    function GetPackageNode: TDOMNode; // the lazarus project or package
    function GetPackageName: string;
    function GetModuleNode: TDOMNode; // the unit
    function GetModuleName: string;
    function GetModuleTopicCount: Integer;
    function GetModuleTopicName(Index: Integer): String;
    function GetModuleTopic(Name: String): TDOMNode;
    function CreateModuleTopic(Name: String): TDOMNode;
    function GetFirstElement: TDOMNode;
    function GetElementWithName(const ElementName: string;
                                CreateIfNotExists: boolean = false): TDOMNode;
    function GetChildValuesAsString(Node: TDOMNode): String;
    function GetValuesFromNode(Node: TDOMNode): TFPDocElementValues;
    function GetValueFromNode(Node: TDOMNode; Item: TFPDocItem): string;
    procedure SetChildValue(Node: TDOMNode; const ChildName: string; NewValue: string);
    procedure DocChanging;
    procedure DocChanged;
    procedure BeginUpdate;
    procedure EndUpdate;
  end;

  { TLazFPDocNode }

  TLazFPDocNode = class
  public
    DocFile: TLazFPDocFile;
    Node: TDomNode;
    constructor Create(AFile: TLazFPDocFile; ANode: TDOMNode);
  end;
  
  { TCHSourceToFPDocFile - cache item for source to FPDoc file mapping }

  TCHSourceToFPDocFile = class
  public
    SourceFilename: string;
    FPDocFilename: string;
    FPDocFileOwner: TObject; // always check FPDocFilenameTimeStamp before accessing
    FPDocFilenameTimeStamp: integer; // corresponds to CompilerParseStamp
    FilesTimeStamp: int64; // corresponds to FileStateCache.TimeStamp
    function IsValid: boolean;
    procedure MakeValid;
  end;
  
  { TCodeHelpElement - mapping between one codetools position and a fpdoc xml node.
    This data is only valid as long as codetools data and fpdoc data are not
    changed, so don't store it. }

  TCodeHelpElement = class
  public
    CodeContext: TFindContext;
    CodeXYPos: TCodeXYPosition;
    ElementOwnerName: string;// the 'fpdoc package' = the name of the lazarus package or project
    ElementUnitName: string;
    ElementUnitFileName: string;
    ElementName: string;
    ElementNode: TDOMNode; // nil = not yet parsed (ElementNodeValid=false) or does not exist (ElementNodeValid=true)
    ElementNodeValid: boolean;
    FPDocFile: TLazFPDocFile;
    procedure WriteDebugReport;
  end;
  
  { TCodeHelpElementChain - a list of TCodeHelpElement.
    For example the list of one element plus its ancestors.
    Only valid for short time. So always check IsValid. }

  TCodeHelpElementChain = class
  private
    FItems: TFPList; // list of TCodeHelpElement
    function GetCount: integer;
    function GetItems(Index: integer): TCodeHelpElement;
    function Add: TCodeHelpElement;
  public
    CodePos: TCodePosition;
    IDEChangeStep: integer; // corresponds to CompilerParseStamp
    CodetoolsChangeStep: integer; // corresponds to CodeToolBoss.CodeTreeNodesDeletedStep
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    property Items[Index: integer]: TCodeHelpElement read GetItems; default;
    property Count: integer read GetCount;
    function IndexOfFile(AFile: TLazFPDocFile): integer;
    function IndexOfElementName(ElementName: string): integer;
    function IndexOfElementName(ElementUnitName, ElementName: string): integer;
    function IsValid: boolean;
    procedure MakeValid;
    function DocFile: TLazFPDocFile; // DocFile of first element
    procedure WriteDebugReport;
  end;
  
  TCodeHelpChangeEvent = procedure(Sender: TObject; LazFPDocFile: TLazFPDocFile) of object;
  
  TCodeHelpManagerHandler = (
    chmhDocChanging,
    chmhDocChanged
    );

  TCodeHelpOpenFileFlag = (
    chofUpdateFromDisk,
    chofRevert,
    chofQuiet
    );
  TCodeHelpOpenFileFlags = set of TCodeHelpOpenFileFlag;
    
  TCodeHelpParseResult = (
    chprParsing, // means: done a small step, but not yet finished the job
    chprFailed,
    chprSuccess
    );

  TCodeHelpHintOption = (
    chhoSmallStep,    // do the next step. Use this to run on idle.
    chhoDeclarationHeader, // add a header with source position and type of identifier
    chhoNoComments    // do not add the pasdoc comments
  );
  TCodeHelpHintOptions = set of TCodeHelpHintOption;
    
  { TCodeHelpManager }

  TCodeHelpManager = class(TComponent)
  private
    FDocs: TAvgLvlTree;// tree of loaded TLazFPDocFile
    FHandlers: array[TCodeHelpManagerHandler] of TMethodList;
    FPasHighlighter: TSynPasSyn;
    FSrcToDocMap: TAvgLvlTree; // tree of TCHSourceToFPDocFile sorted for SourceFilename
    FDeclarationCache: TDeclarationInheritanceCache;
    procedure AddHandler(HandlerType: TCodeHelpManagerHandler;
                         const AMethod: TMethod; AsLast: boolean = false);
    procedure RemoveHandler(HandlerType: TCodeHelpManagerHandler;
                            const AMethod: TMethod);
    procedure FreeHandlers;
    procedure CallDocChangeEvents(HandlerType: TCodeHelpManagerHandler;
                                  Doc: TLazFPDocFile);
    function DoCreateFPDocFileForSource(const SrcFilename: string;
                                        out NewOwner: TObject): string;
    function CreateFPDocFile(const ExpandedFilename, PackageName,
                             ModuleName: string): TCodeBuffer;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure FreeDocs;
    procedure ClearSrcToDocMap;

    function FindFPDocFile(const Filename: string): TLazFPDocFile;
    function LoadFPDocFile(const Filename: string;
                           Flags: TCodeHelpOpenFileFlags;
                           out ADocFile: TLazFPDocFile;
                           out CacheWasUsed: boolean): TCodeHelpParseResult;
    function SaveFPDocFile(ADocFile: TLazFPDocFile): TModalResult;
    function GetFPDocFilenameForHelpContext(
                                       Context: TPascalHelpContextList;
                                       out CacheWasUsed: boolean): string;
    function GetFPDocFilenameForSource(SrcFilename: string;
                                       ResolveIncludeFiles: Boolean;
                                       out CacheWasUsed: boolean;
                                       out AnOwner: TObject;// a package or a project or LazarusHelp or nil for user defined
                                       CreateIfNotExists: boolean = false): string;
    function GetFPDocFilenameForPkgFile(PkgFile: TPkgFile;
                                    ResolveIncludeFiles: Boolean;
                                    out CacheWasUsed: boolean;
                                    CreateIfNotExists: boolean = false): string;
    procedure GetFPDocFilenamesForSources(SrcFilenames: TStringToStringTree;
                      ResolveIncludeFiles: boolean;
                      var FPDocFilenames: TStringToStringTree // Names=Filename, Values=ModuleName
                      );
    function GetIDESrcFPDocPath: string; // $(LazarusDir)/docs/xml/ide/
    function IsIDESrcFile(const SrcFilename: string): boolean;
    function FindModuleOwner(const Modulename: string): TObject;
    function FindModuleOwner(FPDocFile: TLazFPDocFile): TObject;
    function GetModuleOwnerName(TheOwner: TObject): string;
    function ExpandFPDocLinkID(const LinkID, DefaultUnitName,
                               DefaultOwnerName: string): string;
    function ExpandFPDocLinkID(const LinkID, DefaultUnitName: string;
                               TheOwner: TObject): string;
    function CodeNodeToElementName(Tool: TFindDeclarationTool;
                                   CodeNode: TCodeTreeNode): string;
    function GetFPDocNode(Tool: TCodeTool; CodeNode: TCodeTreeNode; Complete: boolean;
                          out FPDocFile: TLazFPDocFile; out DOMNode: TDOMNode;
                          out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetLinkedFPDocNode(StartFPDocFile: TLazFPDocFile;
                          StartDOMNode: TDOMNode;
                          const Path: string;
                          Flags: TCodeHelpOpenFileFlags;
                          out ModuleOwner: TObject;
                          out FPDocFile: TLazFPDocFile; out DOMNode: TDOMNode;
                          out InvalidPath: integer;
                          out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetDeclarationChain(Code: TCodeBuffer; X, Y: integer;
                                 out ListOfPCodeXYPosition: TFPList;
                                 out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetCodeContext(CodePos: PCodeXYPosition;
                            out FindContext: TFindContext;
                            Complete: boolean;
                            out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetElementChain(Code: TCodeBuffer; X, Y: integer; Complete: boolean;
                             out Chain: TCodeHelpElementChain;
                             out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetHTMLHint(Code: TCodeBuffer; X, Y: integer; Options: TCodeHelpHintOptions;
                     out BaseURL, HTMLHint: string;
                     out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetHTMLHint2(Code: TCodeBuffer; X, Y: integer; Options: TCodeHelpHintOptions;
                     out BaseURL, HTMLHint: string;
                     out CacheWasUsed: boolean): TCodeHelpParseResult;
    function GetPasDocCommentsAsHTML(Tool: TFindDeclarationTool; Node: TCodeTreeNode): string;
    function GetFPDocNodeAsHTML(FPDocFile: TLazFPDocFile; DOMNode: TDOMNode): string;
    function TextToHTML(Txt: string): string;
    function CreateElement(Code: TCodeBuffer; X, Y: integer;
                           out Element: TCodeHelpElement): Boolean;
    function SourceToFPDocHint(Src: string; NestedComments: boolean = true): string;
    function SourcePosToFPDocHint(XYPos: TCodeXYPosition; Caption: string=''): string;
    function SourcePosToFPDocHint(const aFilename: string; X,Y: integer;
                                  Caption: string=''): string;
    function OwnerToFPDocHint(AnOwner: TObject): string;
  public
    // Event lists
    procedure RemoveAllHandlersOfObject(AnObject: TObject);
    procedure AddHandlerOnChanging(const OnDocChangingEvent: TCodeHelpChangeEvent;
                                   AsLast: boolean = false);
    procedure RemoveHandlerOnChanging(const OnDocChangingEvent: TCodeHelpChangeEvent);
    procedure AddHandlerOnChanged(const OnDocChangedEvent: TCodeHelpChangeEvent;
                                  AsLast: boolean = false);
    procedure RemoveHandlerOnChanged(const OnDocChangedEvent: TCodeHelpChangeEvent);
  public
    property PasHighlighter: TSynPasSyn read FPasHighlighter;
  end;

  TFPDocHintToken = (
    fpdhtText,
    fpdhtKeyword,
    fpdhtString,
    fpdhtNumber,
    fpdhtSymbol
    );
  TFPDocHintTokens = set of TFPDocHintToken;

var
  CodeHelpBoss: TCodeHelpManager = nil;// set by the IDE
  
function CompareLazFPDocFilenames(Data1, Data2: Pointer): integer;
function CompareAnsistringWithLazFPDocFile(Key, Data: Pointer): integer;
function CompareLDSrc2DocSrcFilenames(Data1, Data2: Pointer): integer;
function CompareAnsistringWithLDSrc2DocSrcFile(Key, Data: Pointer): integer;

function ToUnixLineEnding(const s: String): String;
function ToOSLineEnding(const s: String): String;
function ReplaceLineEndings(const s, NewLineEnds: string): string;
function AppendLineEnding(const s: string): string; // append if not empty and there is not already a line ending

implementation

function ToUnixLineEnding(const s: String): String;
var
  p: Integer;
begin
  Result:=s;
  p:=1;
  while (p<=length(Result)) do begin
    case Result[p] of
    #10:
      if (p<length(Result)) and (Result[p+1] in [#10,#13])
      and (Result[p]<>Result[p+1]) then begin
        // double character line ending
        System.Delete(Result,p,2);
      end;
    #13:
      begin
        // single char line ending #13
        Result[p]:=#10;
      end;
    end;
    inc(p);
  end;
end;

function ToOSLineEnding(const s: String): String;
const
  le: shortstring = LineEnding;
var
  p: Integer;
begin
  Result:=s;
  p:=1;
  while (p<=length(Result)) do begin
    if not (Result[p] in [#10,#13]) then begin
      inc(p);
    end else begin
      // line ending
      if (p<length(Result)) and (Result[p+1] in [#10,#13]) and (Result[p]<>Result[p+1]) then begin
        // double character line ending
        if (length(le)<>2)
        or (le[1]<>Result[p]) or (le[2]<>Result[p+1]) then begin
          Result:=copy(Result,1,p-1)+le+copy(Result,p+2,length(Result));
          inc(p, length(le)-1);
        end
        else
          inc(p);
      end else begin
        // single char line ending #13 or #10
        if (length(le)<>1)
        or (le[1]<>Result[p]) then begin
          Result:=copy(Result,1,p-1)+le+copy(Result,p+1,length(Result));
          inc(p, length(le)-1);
        end;
      end;
      inc(p);
    end;
  end;
end;

function ReplaceLineEndings(const s, NewLineEnds: string): string;
var
  p: Integer;
  StartPos: LongInt;
begin
  Result:=s;
  p:=1;
  while (p<=length(Result)) do begin
    if Result[p] in [#10,#13] then begin
      StartPos:=p;
      if (p<length(Result))
      and (Result[p+1] in [#10,#13]) and (Result[p]<>Result[p+1]) then
        inc(p);
      Result:=copy(Result,1,StartPos-1)+NewLineEnds+copy(Result,p+1,length(Result));
      inc(p,length(NewLineEnds));
    end else begin
      inc(p);
    end;
  end;
end;

function AppendLineEnding(const s: string): string;
begin
  Result:=s;
  if (Result='') or (Result[length(Result)] in [#10,#13]) then exit;
  Result:=Result+LineEnding;
end;

function CompareLazFPDocFilenames(Data1, Data2: Pointer): integer;
begin
  Result:=CompareFilenames(TLazFPDocFile(Data1).Filename,
                           TLazFPDocFile(Data2).Filename);
end;

function CompareAnsistringWithLazFPDocFile(Key, Data: Pointer): integer;
begin
  Result:=CompareFilenames(AnsiString(Key),TLazFPDocFile(Data).Filename);
end;

function CompareLDSrc2DocSrcFilenames(Data1, Data2: Pointer): integer;
begin
  Result:=CompareFilenames(TCHSourceToFPDocFile(Data1).SourceFilename,
                           TCHSourceToFPDocFile(Data2).SourceFilename);
end;

function CompareAnsistringWithLDSrc2DocSrcFile(Key, Data: Pointer): integer;
begin
  Result:=CompareFilenames(AnsiString(Key),TCHSourceToFPDocFile(Data).SourceFilename);
end;

{ TCHSourceToFPDocFile }

function TCHSourceToFPDocFile.IsValid: boolean;
begin
  Result:=(FPDocFilenameTimeStamp=CompilerParseStamp)
      and (FilesTimeStamp=FileStateCache.TimeStamp)
end;

procedure TCHSourceToFPDocFile.MakeValid;
begin
  FPDocFilenameTimeStamp:=CompilerParseStamp;
  FilesTimeStamp:=FileStateCache.TimeStamp;
end;

{ TLazFPDocFile }

destructor TLazFPDocFile.Destroy;
begin
  FreeAndNil(Doc);
  inherited Destroy;
end;

function TLazFPDocFile.GetPackageNode: TDOMNode;
begin
  Result:=nil;
  if Doc=nil then exit;

  // get first node
  Result := Doc.FindNode('fpdoc-descriptions');
  if Result=nil then begin
    //DebugLn(['TLazFPDocFile.GetPackageNode fpdoc-descriptions not found']);
    exit;
  end;

  // proceed to package
  Result := Result.FindNode('package');
end;

function TLazFPDocFile.GetPackageName: string;
var
  Node: TDOMNode;
begin
  Node:=GetPackageNode;
  if Node is TDOMElement then
    Result:=TDomElement(Node).GetAttribute('name')
  else
    Result:='';
end;

function TLazFPDocFile.GetModuleNode: TDOMNode;
begin
  Result:=GetPackageNode;
  if Result=nil then begin
    //DebugLn(['TLazFPDocFile.GetModuleNode fpdoc-descriptions has no package']);
    exit;
  end;

  // proceed to module
  Result := Result.FindNode('module');
end;

function TLazFPDocFile.GetModuleName: string;
var
  Node: TDOMNode;
begin
  Node:=GetModuleNode;
  if Node is TDOMElement then
    Result:=TDomElement(Node).GetAttribute('name')
  else
    Result:='';
end;

function TLazFPDocFile.GetModuleTopicCount: Integer;
var
  n: TDOMNode;
begin
  Result := 0;
  n := GetModuleNode;
  if n = nil then exit;
  n := n.FirstChild;
  while (n <> nil) do begin
    if (n.NodeName = 'topic') then inc(result);
    n := n.NextSibling;
  end;
end;

function TLazFPDocFile.GetModuleTopicName(Index: Integer): String;
var
  n: TDOMNode;
begin
  Result := '';
  n := GetModuleNode;
  if n = nil then exit;
  n := n.FirstChild;
  while (n <> nil) and (Index >= 0) do begin
    if (n.NodeName = 'topic') and (n is TDomElement) then begin
      if Index = 0 then begin
        Result := TDomElement(n).GetAttribute('name');
        exit;
      end;
      dec(Index);
    end;
    n := n.NextSibling;
  end;
end;

function TLazFPDocFile.GetModuleTopic(Name: String): TDOMNode;
begin
  Result := GetModuleNode;
  if Result = nil then exit;
  Result := Result.FirstChild;
  while (Result <> nil) do begin
    if (Result.NodeName = 'topic') and (Result is TDomElement) and
        (SysUtils.CompareText(TDomElement(Result).GetAttribute('name'), Name) = 0)
    then
      exit;
    Result := Result.NextSibling;
  end;
end;

function TLazFPDocFile.CreateModuleTopic(Name: String): TDOMNode;
var
  ModuleNode: TDOMNode;
begin
  ModuleNode := GetModuleNode;
  if ModuleNode = nil then exit;

  Result:=Doc.CreateElement('topic');
  DocChanging;
  TDOMElement(Result).SetAttribute('name', Name);
  ModuleNode.AppendChild(Result);
  DocChanged;
end;

function TLazFPDocFile.GetFirstElement: TDOMNode;
begin
  //get first module node
  Result := GetModuleNode;
  //DebugLn(['TLazFPDocFile.GetFirstElement GetModuleNode=',GetModuleNode<>nil]);
  if Result=nil then exit;

  //proceed to element
  Result := Result.FirstChild;
  while (Result<>nil) and (Result.NodeName <> 'element') do
    Result := Result.NextSibling;
end;

function TLazFPDocFile.GetElementWithName(const ElementName: string;
  CreateIfNotExists: boolean): TDOMNode;
var
  ModuleNode: TDOMNode;
begin
  Result:=nil;
  // get first module node
  ModuleNode:=GetModuleNode;
  if ModuleNode=nil then begin
    if CreateIfNotExists then
      DebugLn(['TLazFPDocFile.GetElementWithName create failed: missing module name. ElementName=',ElementName]);
    exit;
  end;
  // check module name
  if (ModuleNode is TDomElement)
  and (SysUtils.CompareText(TDomElement(ModuleNode).GetAttribute('name'),ElementName)=0)
  then begin
    Result:=ModuleNode;
    exit;
  end;
  // check elements
  Result:=GetFirstElement;
  //DebugLn(['TLazFPDocFile.GetElementWithName ',ElementName,' GetFirstElement=',GetFirstElement<>nil]);
  while Result<>nil do begin
    //DebugLn(['TLazFPDocFile.GetElementWithName ',dbgsName(Result)]);
    //if Result is TDomElement then DebugLn(['TLazFPDocFile.GetElementWithName ',TDomElement(Result).GetAttribute('name')]);
    if (Result is TDomElement)
    and (SysUtils.CompareText(TDomElement(Result).GetAttribute('name'),ElementName)=0)
    then
      exit;
    Result:=Result.NextSibling;
  end;
  if (Result=nil) and CreateIfNotExists then begin
    DebugLn(['TLazFPDocFile.GetElementWithName creating ',ElementName]);
    Result:=Doc.CreateElement('element');
    DocChanging;
    TDOMElement(Result).SetAttribute('name',ElementName);
    ModuleNode.AppendChild(Result);
    DocChanged;
  end;
end;

function TLazFPDocFile.GetChildValuesAsString(Node: TDOMNode): String;

  procedure FindEndOfTag(const Src: string; var EndPos: integer);
  begin
    while (EndPos<=length(Src)) do begin
      if (Src[EndPos]='>') then begin
        inc(EndPos);
        exit;
      end else if Src[EndPos]='"' then begin
        repeat
          inc(EndPos);
        until (EndPos>=length(Src)) or (Src[EndPos]='"');
      end;
      inc(EndPos);
    end;
  end;

var
  MemStream: TMemoryStream;
  StartPos: Integer;
  EndPos: Integer;
begin
  Result:='';
  MemStream:=TMemoryStream.Create;
  try
    // write node with children
    WriteXML(Node,MemStream);
    MemStream.Position:=0;
    SetLength(Result,MemStream.Size);
    if Result<>'' then
      MemStream.Read(Result[1],length(Result));
    // remove enclosing tag(s) for Node, because Result should only
    // contain the child values:
    //   <nodename/> or <nodename>...<nodename/>
    //   <nodename something=""/>
    //   plus line ends
    StartPos:=1;
    EndPos:=length(Result)+1;
    // skip start tag and spaces at start
    while (StartPos<=length(Result))
    and (Result[StartPos] in [' ',#9,#10,#13]) do
      inc(StartPos);
    if (StartPos<=length(Result)) and (Result[StartPos]='<') then begin
      inc(StartPos);
      FindEndOfTag(Result,StartPos);
      while (StartPos<=length(Result))
      and (Result[StartPos] in [' ',#9,#10,#13]) do
        inc(StartPos);
    end;
    // skip ending line ends and spaces at end
    while (EndPos>StartPos) and (Result[EndPos-1] in [' ',#9,#10,#13]) do
      dec(EndPos);
    // skip end tag
    if (EndPos>StartPos) and (Result[EndPos-1]='>') then begin
      repeat
        dec(EndPos);
        if (EndPos=StartPos) then break;
        if (Result[EndPos-1]='"') then begin
          repeat
            dec(EndPos);
          until (EndPos=StartPos) or (Result[EndPos]='"');
        end else if (Result[EndPos-1]='<') then begin
          dec(EndPos);
          break;
        end;
      until false;
      while (EndPos>StartPos) and (Result[EndPos-1] in [' ',#9,#10,#13]) do
        dec(EndPos);
    end;
    Result:=copy(Result,StartPos,EndPos-StartPos);
    
    // the xml writer adds/removes spaces/new lines automatically
    // add newlines after br and p tags
    StartPos:=1;
    while StartPos<length(Result) do begin
      if Result[StartPos]='<' then begin
        // search end of tag
        EndPos:=StartPos+1;
        FindEndOfTag(Result,EndPos);
        if Result[StartPos+1]='/' then
          inc(StartPos);
        if (CompareIdentifiers(@Result[StartPos+1],'br')=0)
            or (CompareIdentifiers(@Result[StartPos+1],'p')=0) then
        begin
          // add new line
          if (EndPos <= Length(Result)) and not (Result[EndPos] in [#10,#13]) then
            Result:=copy(Result,1,EndPos-1)+LineEnding+copy(Result,EndPos,length(Result));
        end;
        StartPos:=EndPos;
      end else begin
        inc(StartPos);
      end;
    end;
  finally
    MemStream.Free;
  end;
  {$ifdef VerboseLazDoc}
  if Result<>'' then
    DebugLn(['TLazFPDocFile.GetChildValuesAsString Node=',Node.NodeName,' Result=',Result]);
  {$endif}
end;

function TLazFPDocFile.GetValuesFromNode(Node: TDOMNode): TFPDocElementValues;
// simple function to return the values as string
var
  S: String;
begin
  //DebugLn(['TLazFPDocFile.GetValuesFromNode ',Node.NodeName,' ',dbgsName(Node),' ',Node is TDomElement]);
  if Node is TDomElement then
    Result[fpdiElementLink] := TDomElement(Node).GetAttribute('link');
  Node := Node.FirstChild;
  while Assigned(Node) do
  begin
    if (Node.NodeType = ELEMENT_NODE) then
    begin
      S := Node.NodeName;
      if S = FPDocItemNames[fpdiShort] then
        Result[fpdiShort] := GetChildValuesAsString(Node);

      if S = FPDocItemNames[fpdiDescription] then
        Result[fpdiDescription] := GetChildValuesAsString(Node);

      if S = FPDocItemNames[fpdiErrors] then
        Result[fpdiErrors] := GetChildValuesAsString(Node);

      if S = FPDocItemNames[fpdiSeeAlso] then
        Result[fpdiSeeAlso] := GetChildValuesAsString(Node);

      if S = FPDocItemNames[fpdiExample] then
        Result[fpdiExample] := Node.Attributes.GetNamedItem('file').NodeValue;
    end;
    Node := Node.NextSibling;
  end;
end;

function TLazFPDocFile.GetValueFromNode(Node: TDOMNode; Item: TFPDocItem
  ): string;
var
  Child: TDOMNode;
begin
  Result:='';
  Child:=Node.FindNode(FPDocItemNames[Item]);
  //DebugLn(['TLazFPDocFile.GetValueFromNode ',FPDocItemNames[Item],' Found=',Child<>nil]);
  if Child<>nil then begin
    if Item=fpdiExample then
      Result := Child.Attributes.GetNamedItem('file').NodeValue
    else
      Result := GetChildValuesAsString(Child);
  end;
end;

procedure TLazFPDocFile.SetChildValue(Node: TDOMNode; const ChildName: string;
  NewValue: string);
  
  procedure ReadXMLFragmentFromString(AParentNode: TDOMNode; const s: string);
  var
    MemStream: TStream;
  begin
    if s='' then exit;
    try
      MemStream:=TMemoryStream.Create;
      MemStream.Write(s[1],length(s));
      MemStream.Position:=0;
      ReadXMLFragment(AParentNode,MemStream);
    finally
      MemStream.Free;
    end;
  end;
  
var
  Child: TDOMNode;
  FileAttribute, LinkAttribute: TDOMAttr;
begin
  NewValue:=ToOSLineEnding(NewValue);
  if ChildName=FPDocItemNames[fpdiElementLink] then begin
    // update attribute
    if Node is TDomElement then begin
      LinkAttribute:=TDomElement(Node).GetAttributeNode('link');
      if ((NewValue='') and (LinkAttribute<>nil))
      or ((NewValue<>'') and ((LinkAttribute=nil) or (LinkAttribute.NodeValue<>NewValue)))
      then begin
        // delete, add or change attribute 'link'
        DebugLn(['TLazFPDocFile.SetChildValue Changing link Name=',ChildName,' NewValue="',NewValue,'"']);
        DocChanging;
        try
          if NewValue='' then begin
            TDomElement(Node).RemoveAttributeNode(LinkAttribute);
            LinkAttribute.Free;
          end else
            TDomElement(Node).SetAttribute('link',NewValue);
        finally
          DocChanged;
        end;
      end;
    end;
  end else begin
    // update sub node
    Child:=Node.FindNode(ChildName);
    if ChildName = FPDocItemNames[fpdiExample] then begin
      // update sub node example, attribute file
      NewValue:=FilenameToURLPath(NewValue);
      FileAttribute:=nil;
      if Child is TDomElement then
        FileAttribute:=TDomElement(Child).GetAttributeNode('file');
      if ((NewValue='') and (FileAttribute<>nil))
      or ((NewValue<>'') and ((FileAttribute=nil) or (FileAttribute.NodeValue<>NewValue)))
      then begin
        // delete, add or change attribute 'file'
        DebugLn(['TLazFPDocFile.SetChildValue Changing example file Name=',ChildName,' NewValue="',NewValue,'"']);
        DocChanging;
        try
          if NewValue='' then begin
            // remove old content
            while Child.LastChild<>nil do
              Child.RemoveChild(Child.LastChild);
            Node.RemoveChild(Child);
          end else begin
            if Child=nil then begin
              Child := Doc.CreateElement(ChildName);
              Node.AppendChild(Child);
            end;
            TDomElement(Child).SetAttribute('file',NewValue);
          end;
        finally
          DocChanged;
        end;
      end;
    end else begin
      if Child=nil then begin
        // add node
        if NewValue<>'' then begin
          DebugLn(['TLazFPDocFile.SetChildValue Adding Name=',ChildName,' NewValue="',NewValue,'"']);
          DocChanging;
          try
            Child := Doc.CreateElement(ChildName);
            Node.AppendChild(Child);
            ReadXMLFragmentFromString(Child,NewValue);
          finally
            DocChanged;
          end;
        end;
      end else if GetChildValuesAsString(Child)<>NewValue then begin
        // change node
        DocChanging;
        try
          DebugLn(['TLazFPDocFile.SetChildValue Changing ',Node.NodeName,
            ' ChildName=',Child.NodeName,
            ' OldValue=',GetChildValuesAsString(Child),
            ' NewValue="',NewValue,'"']);
          // remove old content
          while Child.LastChild<>nil do
            Child.RemoveChild(Child.LastChild);
          if NewValue='' then begin
            // remove entire child
            Node.RemoveChild(Child);
          end else begin
            // set new content
            ReadXMLFragmentFromString(Child,NewValue);
          end;
        finally
          DocChanged;
        end;
      end;
    end;
  end;
end;

procedure TLazFPDocFile.DocChanging;
begin
  DocModified:=true;
  if (fUpdateLock>0) then begin
    if (ldffDocChangingCalled in FFlags) then exit;
    Include(FFlags,ldffDocChangingCalled);
  end;
  CodeHelpBoss.CallDocChangeEvents(chmhDocChanging,Self);
end;

procedure TLazFPDocFile.DocChanged;
begin
  if (fUpdateLock>0) then begin
    Include(FFlags,ldffDocChangedNeedsCalling);
    exit;
  end;
  Exclude(FFlags,ldffDocChangedNeedsCalling);
  CodeHelpBoss.CallDocChangeEvents(chmhDocChanged,Self);
end;

procedure TLazFPDocFile.BeginUpdate;
begin
  inc(fUpdateLock);
end;

procedure TLazFPDocFile.EndUpdate;
begin
  dec(fUpdateLock);
  if fUpdateLock<0 then RaiseGDBException('TLazFPDocFile.EndUpdate');
  if fUpdateLock=0 then begin
    Exclude(FFlags,ldffDocChangingCalled);
    if ldffDocChangedNeedsCalling in FFlags then
      DocChanged;
  end;
end;

procedure TCodeHelpManager.AddHandler(HandlerType: TCodeHelpManagerHandler;
  const AMethod: TMethod; AsLast: boolean);
begin
  if FHandlers[HandlerType]=nil then
    FHandlers[HandlerType]:=TMethodList.Create;
  FHandlers[HandlerType].Add(AMethod);
end;

procedure TCodeHelpManager.RemoveHandler(HandlerType: TCodeHelpManagerHandler;
  const AMethod: TMethod);
begin
  FHandlers[HandlerType].Remove(AMethod);
end;

procedure TCodeHelpManager.FreeHandlers;
var
  HandlerType: TCodeHelpManagerHandler;
begin
  for HandlerType:=Low(TCodeHelpManagerHandler) to High(TCodeHelpManagerHandler) do
    FreeThenNil(FHandlers[HandlerType]);
end;

procedure TCodeHelpManager.CallDocChangeEvents(HandlerType: TCodeHelpManagerHandler;
  Doc: TLazFPDocFile);
var
  i: LongInt;
begin
  i:=FHandlers[HandlerType].Count;
  while FHandlers[HandlerType].NextDownIndex(i) do
    TCodeHelpChangeEvent(FHandlers[HandlerType].Items[i])(Self,Doc);
end;

function TCodeHelpManager.DoCreateFPDocFileForSource(const SrcFilename: string;
  out NewOwner: TObject): string;
  
  procedure CleanUpPkgList(var PkgList: TFPList);
  var
    i: Integer;
    AProject: TLazProject;
    BaseDir: String;
    APackage: TLazPackage;
  begin
    if (PkgList=nil) then exit;
    for i:=PkgList.Count-1 downto 0 do begin
      if TObject(PkgList[i]) is TLazProject then begin
        AProject:=TLazProject(PkgList[i]);
        BaseDir:=ExtractFilePath(AProject.ProjectInfoFile);
        if BaseDir<>'' then continue;
      end else if TObject(PkgList[i]) is TLazPackage then begin
        APackage:=TLazPackage(PkgList[i]);
        BaseDir:=APackage.DirectoryExpanded;
        if BaseDir<>'' then continue;
      end;
      // this owner can not be used
      PkgList.Delete(i);
    end;
    if PkgList.Count=0 then
      FreeAndNil(PkgList);
      
    if PkgList.Count>1 then begin
      // there are more than one possible owners
      DebugLn(['TCodeHelpManager.DoCreateFPDocFileForSource.CleanUpPkgList Warning: overlapping projects/packages']);
    end;
  end;
  
  function SelectNewLazDocPaths(const Title, BaseDir: string): string;
  begin
    Result:=LazSelectDirectory('Choose LazDoc directory for '+Title,BaseDir);
    if (Result<>'') then
      Result:=CreateRelativePath(Result,BaseDir);
  end;
  
var
  PkgList: TFPList;
  AProject: TLazProject;
  APackage: TLazPackage;
  p: Integer;
  LazDocPaths: String;
  LazDocPackageName: String;
  NewPath: String;
  BaseDir: String;
  Code: TCodeBuffer;
  CurUnitName: String;
  AVLNode: TAvgLvlTreeNode;
begin
  Result:='';
  NewOwner:=nil;
  DebugLn(['TCodeHelpManager.DoCreateFPDocFileForSource ',SrcFilename]);
  if not FilenameIsAbsolute(SrcFilename) then begin
    DebugLn(['TCodeHelpManager.DoCreateFPDocFileForSource failed, because file no absolute: ',SrcFilename]);
    exit;
  end;

  PkgList:=nil;
  try
    // get all packages owning the file
    PkgList:=PackageEditingInterface.GetOwnersOfUnit(SrcFilename);
    CleanUpPkgList(PkgList);
    if (PkgList=nil) then begin
      PkgList:=PackageEditingInterface.GetPossibleOwnersOfUnit(SrcFilename,
                                               [piosfIncludeSourceDirectories]);
      CleanUpPkgList(PkgList);
    end;
    if (PkgList=nil) and IsIDESrcFile(SrcFilename) then begin
      PkgList:=TFPList.Create;
      PkgList.Add(LazarusHelp);
    end;
    if PkgList=nil then begin
      // no package/project found
      MessageDlg(lisProjAddPackageNotFound,
        Format(lisLDTheUnitIsNotOwnedBeAnyPackageOrProjectPleaseAddThe, [
          SrcFilename, #13, #13]), mtError, [mbCancel], 0);
      exit;
    end;

    NewOwner:=TObject(PkgList[0]);
    if NewOwner is TLazProject then begin
      AProject:=TLazProject(NewOwner);
      BaseDir:=ExtractFilePath(AProject.ProjectInfoFile);
      if AProject.LazDocPaths='' then
        AProject.LazDocPaths:=SelectNewLazDocPaths(AProject.ShortDescription,BaseDir);
      LazDocPaths:=AProject.LazDocPaths;
      LazDocPackageName:=GetModuleOwnerName(AProject);
    end else if NewOwner is TLazPackage then begin
      APackage:=TLazPackage(NewOwner);
      BaseDir:=APackage.DirectoryExpanded;
      if APackage.LazDocPaths='' then
        APackage.LazDocPaths:=SelectNewLazDocPaths(APackage.Name,BaseDir);
      LazDocPaths:=APackage.LazDocPaths;
      LazDocPackageName:=GetModuleOwnerName(APackage);
    end else if NewOwner=LazarusHelp then begin
      BaseDir:=EnvironmentOptions.LazarusDirectory;
      LazDocPaths:=GetIDESrcFPDocPath;
      LazDocPackageName:=IDEProjectName;
    end else begin
      DebugLn(['TCodeHelpManager.DoCreateFPDocFileForSource unknown owner type ',dbgsName(NewOwner)]);
      NewOwner:=nil;
      exit;
    end;

    IDEMacros.CreateAbsoluteSearchPath(LazDocPaths,BaseDir);

    p:=1;
    repeat
      NewPath:=GetNextDirectoryInSearchPath(LazDocPaths,p);
      if not FilenameIsAbsolute(NewPath) then
        NewPath:=AppendPathDelim(BaseDir)+NewPath;
      if DirPathExistsCached(NewPath) then begin
        // fpdoc directory found
        Result:=AppendPathDelim(NewPath)+lowercase(ExtractFileNameOnly(SrcFilename))+'.xml';
        Code:=CodeToolBoss.LoadFile(SrcFilename,true,false);
        // get unitname
        CurUnitName:=ExtractFileNameOnly(SrcFilename);
        if Code<>nil then
          CurUnitName:=CodeToolBoss.GetSourceName(Code,false);
        // remove cache (source to fpdoc filename)
        AVLNode:=FSrcToDocMap.FindKey(Pointer(SrcFilename),
                                      @CompareAnsistringWithLDSrc2DocSrcFile);
        if AVLNode<>nil then
          FSrcToDocMap.FreeAndDelete(AVLNode);
        // create fpdoc file
        if CreateFPDocFile(Result,LazDocPackageName,CurUnitName)=nil then
          Result:='';
        exit;
      end;
    until false;
    
    // no valid directory found
    DebugLn(['TCodeHelpManager.DoCreateFPDocFileForSource LazDocModul="',LazDocPackageName,'" LazDocPaths="',LazDocPaths,'" ']);
    MessageDlg(lisLDNoValidLazDocPath,
      Format(lisLDDoesNotHaveAnyValidLazDocPathUnableToCreateTheFpdo, [
        LazDocPackageName, #13, SrcFilename]), mtError, [mbCancel], 0);
  finally
    PkgList.Free;
  end;
end;

function TCodeHelpManager.CreateFPDocFile(const ExpandedFilename,
  PackageName, ModuleName: string): TCodeBuffer;
var
  Doc: TXMLDocument;
  DescrNode: TDOMElement;
  ms: TMemoryStream;
  s: string;
  ModuleNode: TDOMElement;
  PackageNode: TDOMElement;
begin
  Result:=nil;
  if FileExistsCached(ExpandedFilename) then begin
    Result:=CodeToolBoss.LoadFile(ExpandedFilename,true,false);
    exit;
  end;
  Result:=CodeToolBoss.CreateFile(ExpandedFilename);
  if Result=nil then begin
    MessageDlg('Unable to create file',
      'Unable to create file '+ExpandedFilename,mtError,[mbCancel],0);
    exit;
  end;
  
  Doc:=nil;
  ms:=nil;
  try
    Doc:=TXMLDocument.Create;
    // <fpdoc-descriptions>
    DescrNode:=Doc.CreateElement('fpdoc-descriptions');
    Doc.AppendChild(DescrNode);
    //   <package name="packagename">
    PackageNode:=Doc.CreateElement('package');
    PackageNode.SetAttribute('name',PackageName);
    DescrNode.AppendChild(PackageNode);
    //   <module name="unitname">
    ModuleNode:=Doc.CreateElement('module');
    ModuleNode.SetAttribute('name',ModuleName);
    PackageNode.AppendChild(ModuleNode);
    // write the XML to a string
    ms:=TMemoryStream.Create;
    WriteXMLFile(Doc,ms);
    ms.Position:=0;
    SetLength(s,ms.Size);
    if s<>'' then
      ms.Read(s[1],length(s));
    // copy to codebuffer
    //DebugLn(['TCodeHelpManager.CreateFPDocFile ',s]);
    Result.Source:=s;
    // save file
    if SaveCodeBuffer(Result)<>mrOk then
      Result:=nil;
  finally
    ms.Free;
    Doc.Free;
  end;
end;

constructor TCodeHelpManager.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  FDocs:=TAvgLvlTree.Create(@CompareLazFPDocFilenames);
  FSrcToDocMap:=TAvgLvlTree.Create(@CompareLDSrc2DocSrcFilenames);
  FDeclarationCache:=TDeclarationInheritanceCache.Create(
                                  @CodeToolBoss.FindDeclarationAndOverload,
                                  @CodeToolBoss.GetCodeTreeNodesDeletedStep);
  FPasHighlighter:=TSynPasSyn.Create(Self);
end;

destructor TCodeHelpManager.Destroy;
begin
  ClearSrcToDocMap;
  FreeDocs;
  FreeAndNil(FDocs);
  FreeAndNil(FSrcToDocMap);
  FreeAndNil(FDeclarationCache);
  FreeHandlers;
  inherited Destroy;
end;

function TCodeHelpManager.FindFPDocFile(const Filename: string): TLazFPDocFile;
var
  Node: TAvgLvlTreeNode;
begin
  Node:=FDocs.FindKey(Pointer(Filename),@CompareAnsistringWithLazFPDocFile);
  if Node<>nil then
    Result:=TLazFPDocFile(Node.Data)
  else
    Result:=nil;
end;

function TCodeHelpManager.LoadFPDocFile(const Filename: string;
  Flags: TCodeHelpOpenFileFlags;
  out ADocFile: TLazFPDocFile; out CacheWasUsed: boolean
  ): TCodeHelpParseResult;
var
  MemStream: TMemoryStream;
  CurFilename: String;
begin
  Result:=chprFailed;
  CacheWasUsed:=true;
  ADocFile:=FindFPDocFile(Filename);
  if ADocFile=nil then begin
    CacheWasUsed:=false;
    ADocFile:=TLazFPDocFile.Create;
    ADocFile.Filename:=Filename;
    FDocs.Add(ADocFile);
  end;
  ADocFile.CodeBuffer:=CodeToolBoss.LoadFile(Filename,
                               chofUpdateFromDisk in Flags,chofRevert in Flags);
  if ADocFile.CodeBuffer=nil then begin
    DebugLn(['TCodeHelpManager.LoadFPDocFile unable to load "',Filename,'"']);
    FreeAndNil(ADocFile.Doc);
    exit;
  end;
  if (ADocFile.CodeBufferChangeStep=ADocFile.CodeBuffer.ChangeStep) then begin
    // CodeBuffer has not changed
    if ADocFile.DocErrorMsg<>'' then begin
      if not (chofQuiet in Flags) then begin
        // for example: Filename(y,x) Error: description
        IDEMessagesWindow.AddMsg(ADocFile.DocErrorMsg,
                              ExtractFilePath(ADocFile.CodeBuffer.Filename),-1);
      end;
      // no update needed
      exit(chprFailed);
    end;
    if ADocFile.DocModified and (chofRevert in Flags) then begin
      // revert the modifications => rebuild the Doc from the CodeBuffer
    end else begin
      // no update needed
      exit(chprSuccess);
    end;
  end;
  CacheWasUsed:=false;
  
  {$IFDEF VerboseLazDoc}
  DebugLn(['TCodeHelpManager.LoadFPDocFile parsing ',ADocFile.Filename]);
  {$ENDIF}
  CallDocChangeEvents(chmhDocChanging,ADocFile);

  // parse XML
  ADocFile.CodeBufferChangeStep:=ADocFile.CodeBuffer.ChangeStep;
  ADocFile.DocModified:=false;
  ADocFile.DocErrorMsg:='Unknown error';
  FreeAndNil(ADocFile.Doc);
  CurFilename:=ADocFile.CodeBuffer.Filename;

  MemStream:=TMemoryStream.Create;
  try
    ADocFile.CodeBuffer.SaveToStream(MemStream);
    MemStream.Position:=0;
    Result:=chprFailed;
    try
      ReadXMLFile(ADocFile.Doc,MemStream,CurFilename);
      ADocFile.DocErrorMsg:='';
      Result:=chprSuccess;
    except
      on E: EXMLReadError do begin
        ADocFile.DocErrorMsg:=E.Message;
        DebugLn(['TCodeHelpManager.LoadFPDocFile ',E.Message]);
        if not (chofQuiet in Flags) then begin
          // for example: Filename(y,x) Error: description
          IDEMessagesWindow.AddMsg(ADocFile.DocErrorMsg,ExtractFilePath(CurFilename),-1);
        end;
      end;
      on E: Exception do begin
        ADocFile.DocErrorMsg:='Error reading xml file "'+CurFilename+'" '+E.Message;
        DebugLn(['TCodeHelpManager.LoadFPDocFile '+ADocFile.DocErrorMsg]);
        if not (chofQuiet in Flags) then begin
          MessageDlg(lisErrorReadingXML,
            Format(lisErrorReadingXmlFile, ['"', CurFilename,
              '"', #13, E.Message]), mtError, [mbCancel], 0);
        end;
      end;
    end;
  finally
    if Result<>chprSuccess then
      FreeAndNil(ADocFile.Doc);
    MemStream.Free;
    CallDocChangeEvents(chmhDocChanging,ADocFile);
  end;
end;

function TCodeHelpManager.SaveFPDocFile(ADocFile: TLazFPDocFile): TModalResult;
var
  ms: TMemoryStream;
  s: string;
begin
  if (not ADocFile.DocModified)
  and (ADocFile.CodeBufferChangeStep=ADocFile.CodeBuffer.ChangeStep)
  and (not ADocFile.CodeBuffer.FileOnDiskNeedsUpdate) then begin
    DebugLn(['TCodeHelpManager.SaveFPDocFile no save needed: ',ADocFile.Filename]);
    exit(mrOk);
  end;
  if (ADocFile.Doc=nil) then begin
    DebugLn(['TCodeHelpManager.SaveFPDocFile no Doc: ',ADocFile.Filename]);
    exit(mrOk);
  end;
  if not FilenameIsAbsolute(ADocFile.Filename) then begin
    DebugLn(['TCodeHelpManager.SaveFPDocFile no expanded filename: ',ADocFile.Filename]);
    exit(mrCancel);
  end;

  // write Doc to xml stream
  try
    ms:=TMemoryStream.Create;
    WriteXMLFile(ADocFile.Doc, ms);
    ms.Position:=0;
    SetLength(s,ms.Size);
    if s<>'' then
      ms.Read(s[1],length(s));
  finally
    ms.Free;
  end;

  // write to CodeBuffer
  ADocFile.CodeBuffer.Source:=s;
  ADocFile.DocModified:=false;
  if ADocFile.CodeBuffer.ChangeStep=ADocFile.CodeBufferChangeStep then begin
    // doc was not really modified => do not save to keep file date
    DebugLn(['TCodeHelpManager.SaveFPDocFile Doc was not really modified ',ADocFile.Filename]);
    exit(mrOk);
  end;
  ADocFile.CodeBufferChangeStep:=ADocFile.CodeBuffer.ChangeStep;
  
  // write to disk
  Result:=SaveCodeBuffer(ADocFile.CodeBuffer);
  DebugLn(['TCodeHelpManager.SaveFPDocFile saved ',ADocFile.Filename]);
end;

function TCodeHelpManager.GetFPDocFilenameForHelpContext(
  Context: TPascalHelpContextList; out CacheWasUsed: boolean): string;
var
  i: Integer;
  SrcFilename: String;
  AnOwner: TObject;
begin
  Result:='';
  CacheWasUsed:=true;
  if Context=nil then exit;
  for i:=0 to Context.Count-1 do begin
    if Context.Items[i].Descriptor<>pihcFilename then continue;
    SrcFilename:=Context.Items[i].Context;
    Result:=GetFPDocFilenameForSource(SrcFilename,true,CacheWasUsed,AnOwner);
    exit;
  end;
end;

function TCodeHelpManager.GetFPDocFilenameForSource(SrcFilename: string;
  ResolveIncludeFiles: Boolean; out CacheWasUsed: boolean;
  out AnOwner: TObject; CreateIfNotExists: boolean): string;
var
  FPDocName: String;
  SearchedPaths: string;

  function SearchInPath(Paths: string; const BaseDir: string;
    out Filename: string): boolean;
  var
    CurPath: String;
    p: Integer;
  begin
    if Paths='' then exit;
    if not IDEMacros.CreateAbsoluteSearchPath(Paths,BaseDir) then exit;
    //DebugLn(['SearchInPath START ',Paths]);
    if Paths='' then exit;
    p:=1;
    repeat
      CurPath:=GetNextDirectoryInSearchPath(Paths,p);
      if CurPath<>'' then begin
        CurPath:=CleanAndExpandDirectory(CurPath);
        if SearchDirectoryInSearchPath(SearchedPaths,CurPath)<1 then begin
          // not yet searched in this directory
          SearchedPaths:=SearchedPaths+';'+CurPath;
          Filename:=AppendPathDelim(CurPath)+FPDocName;
          if FileExistsCached(Filename) then exit(true);
        end;
      end;
    until p>length(Paths);
    Filename:='';
    Result:=false;
  end;
  
  function CheckUnitOwners(CheckSourceDirectories: boolean;
    out Filename: string): boolean;
  var
    PkgList: TFPList;
    i: Integer;
    APackage: TLazPackage;
    BaseDir: String;
    AProject: TLazProject;
  begin
    Result:=false;
    Filename:='';
    if not FilenameIsAbsolute(SrcFilename) then exit;
    
    if CheckSourceDirectories then begin
      PkgList:=PackageEditingInterface.GetPossibleOwnersOfUnit(SrcFilename,[]);
    end else begin
      PkgList:=PackageEditingInterface.GetOwnersOfUnit(SrcFilename);
    end;
    // get all packages owning the file
    if PkgList=nil then exit;
    try
      for i:=0 to PkgList.Count-1 do begin
        //debugln(['CheckUnitOwners ',DbgSName(TObject(PkgList[i]))]);
        if TObject(PkgList[i]) is TLazProject then begin
          AProject:=TLazProject(PkgList[i]);
          AnOwner:=AProject;
          if AProject.LazDocPaths='' then continue;
          BaseDir:=ExtractFilePath(AProject.ProjectInfoFile);
          if BaseDir='' then continue;
          // add lazdoc paths of project
          if SearchInPath(AProject.LazDocPaths,BaseDir,Filename) then
            exit(true);
        end else if TObject(PkgList[i]) is TLazPackage then begin
          APackage:=TLazPackage(PkgList[i]);
          AnOwner:=APackage;
          if APackage.LazDocPaths='' then continue;
          BaseDir:=APackage.Directory;
          if BaseDir='' then continue;
          // add lazdoc paths of package
          if SearchInPath(APackage.LazDocPaths,BaseDir,Filename) then begin
            exit(true);
          end else if AnOwner=nil then
            AnOwner:=APackage;
        end;
      end;
    finally
      PkgList.Free;
    end;
  end;
  
  function CheckIfInLazarus(out Filename: string): boolean;
  begin
    Result:=false;
    Filename:='';
    if not FilenameIsAbsolute(SrcFilename) then exit;
    // check IDE directories
    if IsIDESrcFile(SrcFilename) then begin
      AnOwner:=LazarusHelp;
      if SearchInPath(GetIDESrcFPDocPath,'',Filename) then
        exit(true);
    end;

    // finally: check if in user directories
    if SearchInPath(EnvironmentOptions.LazDocPaths,'',Filename) then
    begin
      AnOwner:=nil;
      exit(true);
    end;
  end;

var
  CodeBuf: TCodeBuffer;
  AVLNode: TAvgLvlTreeNode;
  MapEntry: TCHSourceToFPDocFile;
begin
  Result:='';
  CacheWasUsed:=true;
  AnOwner:=nil;

  if ResolveIncludeFiles then begin
    CodeBuf:=CodeToolBoss.FindFile(SrcFilename);
    if CodeBuf<>nil then begin
      CodeBuf:=CodeToolBoss.GetMainCode(CodeBuf);
      if CodeBuf<>nil then begin
        SrcFilename:=CodeBuf.Filename;
      end;
    end;
  end;
  
  if not FilenameIsPascalSource(SrcFilename) then
  begin
    DebugLn(['TCodeHelpManager.GetFPDocFilenameForSource error: not a source file: "',SrcFilename,'"']);
    exit;
  end;
  
  try
    // first try cache
    MapEntry:=nil;
    AVLNode:=FSrcToDocMap.FindKey(Pointer(SrcFilename),
                                  @CompareAnsistringWithLDSrc2DocSrcFile);
    if AVLNode<>nil then begin
      MapEntry:=TCHSourceToFPDocFile(AVLNode.Data);
      if MapEntry.IsValid then begin
        AnOwner:=MapEntry.FPDocFileOwner;
        Result:=MapEntry.FPDocFilename;
        exit;
      end;
    end;
    CacheWasUsed:=false;

    {$IFDEF VerboseLazDoc}
    DebugLn(['TCodeHelpManager.GetFPDocFilenameForSource searching SrcFilename=',SrcFilename]);
    {$ENDIF}

    // first check if the file is owned by any project/package
    SearchedPaths:='';
    FPDocName:=lowercase(ExtractFileNameOnly(SrcFilename))+'.xml';
    if (not CheckUnitOwners(false,Result)) // first check if file is owned by a package/project
    and (not CheckUnitOwners(true,Result))// then check if the file is in a source directory of a package/project
    and (not CheckIfInLazarus(Result))
    then begin
      // not found
      if AnOwner=nil then
        DebugLn(['TCodeHelpManager.GetFPDocFilenameForSource Hint: file without owner: ',SrcFilename])
      else
        debugln(['TCodeHelpManager.GetFPDocFilenameForSource Hint: Owner has no lazdoc paths: ',SrcFilename]);
    end;

    // save to cache
    if MapEntry=nil then begin
      MapEntry:=TCHSourceToFPDocFile.Create;
      MapEntry.SourceFilename:=SrcFilename;
      FSrcToDocMap.Add(MapEntry);
    end;
    MapEntry.FPDocFilename:=Result;
    MapEntry.FPDocFileOwner:=AnOwner;
    MapEntry.MakeValid;
  finally
    if (Result='') and CreateIfNotExists then begin
      Result:=DoCreateFPDocFileForSource(SrcFilename,AnOwner);
    end;
    {$IFDEF VerboseLazDoc}
    DebugLn(['TCodeHelpManager.GetFPDocFilenameForSource SrcFilename="',SrcFilename,'" Result="',Result,'"']);
    {$ENDIF}
  end;
  {$ifdef VerboseLazDoc}
  DebugLn(['TCodeHelpManager.GetFPDocFilenameForSource ',dbgsName(AnOwner)]);
  {$endif}
end;

function TCodeHelpManager.GetFPDocFilenameForPkgFile(PkgFile: TPkgFile;
  ResolveIncludeFiles: Boolean; out CacheWasUsed: boolean;
  CreateIfNotExists: boolean): string;
var
  APackage: TLazPackage;
  BaseDir: String;
  SrcFilename: String;
  CodeBuf: TCodeBuffer;
begin
  Result:='';
  CacheWasUsed:=false;
  APackage:=TLazPackage(PkgFile.LazPackage);
  if APackage.LazDocPaths='' then exit;
  BaseDir:=APackage.DirectoryExpanded;
  if BaseDir='' then exit;

  SrcFilename:=PkgFile.Filename;
  if ResolveIncludeFiles then begin
    CodeBuf:=CodeToolBoss.FindFile(SrcFilename);
    if CodeBuf<>nil then begin
      CodeBuf:=CodeToolBoss.GetMainCode(CodeBuf);
      if CodeBuf<>nil then begin
        SrcFilename:=CodeBuf.Filename;
      end;
    end;
  end;

  if not FilenameIsPascalUnit(SrcFilename) then exit;
  SrcFilename:=ExtractFileNameOnly(SrcFilename)+'.xml';

  Result:=SearchFileInPath(SrcFilename,BaseDir,APackage.LazDocPaths,';',
                           ctsfcDefault);
end;

procedure TCodeHelpManager.GetFPDocFilenamesForSources(
  SrcFilenames: TStringToStringTree; ResolveIncludeFiles: boolean;
  var FPDocFilenames: TStringToStringTree);
var
  Node: TAvgLvlTreeNode;
  Item: PStringToStringItem;
  SrcFilename: String;
  CacheWasUsed: boolean;
  AnOwner: TObject;
  FPDocFilename: String;
begin
  Node:=SrcFilenames.Tree.FindLowest;
  while Node<>nil do begin
    Item:=PStringToStringItem(Node.Data);
    SrcFilename:=Item^.Name;
    FPDocFilename:=GetFPDocFilenameForSource(SrcFilename,ResolveIncludeFiles,
                                             CacheWasUsed,AnOwner);
    //DebugLn(['TCodeHelpManager.GetFPDocFilenamesForSources FPDoc=',FPDocFilename,' Src=',SrcFilename]);
    if FPDocFilename<>'' then begin
      if FPDocFilenames=nil then
        FPDocFilenames:=CreateFilenameToStringTree;
      FPDocFilenames[FPDocFilename]:=GetModuleOwnerName(AnOwner);
    end;
    Node:=SrcFilenames.Tree.FindSuccessor(Node);
  end;
end;

function TCodeHelpManager.GetIDESrcFPDocPath: string;
var
  LazDir: String;
begin
  Result:='';
  LazDir:=AppendPathDelim(EnvironmentOptions.LazarusDirectory);
  if (LazDir='') or not FilenameIsAbsolute(LazDir) then exit;
  Result:=LazDir+SetDirSeparators('docs/xml/ide/');
end;

function TCodeHelpManager.IsIDESrcFile(const SrcFilename: string): boolean;
var
  LazDir: String;
begin
  Result:=false;
  LazDir:=AppendPathDelim(EnvironmentOptions.LazarusDirectory);
  if (LazDir='') or not FilenameIsAbsolute(LazDir) then exit;
  if not FileIsInPath(SrcFilename,LazDir) then exit;
  // check if SrcFilename is in one of the IDE directories or sub directories
  if FileIsInPath(SrcFilename,LazDir+'ide')
  or FileIsInPath(SrcFilename,LazDir+'debugger')
  or FileIsInPath(SrcFilename,LazDir+'packager')
  or FileIsInPath(SrcFilename,LazDir+'converter')
  then
    Result:=true;
end;

function TCodeHelpManager.FindModuleOwner(const Modulename: string): TObject;
var
  AProject: TLazProject;
begin
  // check project
  AProject:=LazarusIDE.ActiveProject;
  if (AProject<>nil)
  and (SysUtils.CompareText(GetModuleOwnerName(AProject),Modulename)=0)
  then begin
    Result:=AProject;
    exit;
  end;
  // check package
  Result:=PackageGraph.FindAPackageWithName(Modulename,nil);
  if Result<>nil then exit;
  // check IDE as project
  if SysUtils.CompareText(IDEProjectName,Modulename)=0 then begin
    Result:=LazarusHelp;
    exit;
  end;
  Result:=nil;
end;

function TCodeHelpManager.FindModuleOwner(FPDocFile: TLazFPDocFile): TObject;
var
  AProject: TLazProject;
  Path: String;
  p: PChar;
  PkgName: String;

  function InPackage(Pkg: TLazPackage): boolean;
  var
    SearchPath: String;
  begin
    Result:=false;
    if (Pkg=nil) or (Pkg.LazDocPaths='') then exit;
    // check if the file is in the search path
    Path:=ExtractFilePath(FPDocFile.Filename);
    SearchPath:=Pkg.LazDocPaths;
    if not IDEMacros.CreateAbsoluteSearchPath(SearchPath,Pkg.Directory)
    then
      exit;
    SearchPath:=MinimizeSearchPath(SearchPath);
    //DebugLn(['InPackage Path="',Path,'" SearchPath="',SearchPath,'"']);
    p:=FindPathInSearchPath(PChar(Path),length(Path),
                            PChar(SearchPath),length(SearchPath));
    if p<>nil then begin
      FindModuleOwner:=Pkg;
      Result:=true;
    end;
  end;

var
  Pkg: TLazPackage;
  SearchPath: String;
  i: Integer;
begin
  Result:=nil;
  if FPDocFile=nil then exit;
  AProject:=LazarusIDE.ActiveProject;

  // virtual files belong to the project
  if not FilenameIsAbsolute(Path) then begin
    Result:=AProject;
    exit;
  end;

  // check if in the doc path of the project
  if (AProject<>nil) and (AProject.LazDocPaths<>'')
  and FilenameIsAbsolute(AProject.ProjectInfoFile) then begin
    Path:=ExtractFilePath(FPDocFile.Filename);
    SearchPath:=AProject.LazDocPaths;
    IDEMacros.CreateAbsoluteSearchPath(SearchPath,
                                     ExtractFilePath(AProject.ProjectInfoFile));
    SearchPath:=TrimSearchPath(SearchPath,'');
    p:=FindPathInSearchPath(PChar(Path),length(Path),
                            PChar(SearchPath),length(SearchPath));
    if p<>nil then begin
      Result:=AProject;
      exit;
    end;
  end;

  // check the packagename in the fpdoc file
  PkgName:=FPDocFile.GetPackageName;
  if PkgName<>'' then begin
    Pkg:=PackageGraph.FindAPackageWithName(PkgName,nil);
    if InPackage(Pkg) then exit;
  end;

  // search in all packages
  for i:=0 to PackageGraph.Count-1 do
    if InPackage(PackageGraph.Packages[i]) then exit;

  // check the IDE
  SearchPath:=GetIDESrcFPDocPath;
  if (SearchPath<>'') and FileIsInPath(FPDocFile.Filename,SearchPath) then
  begin
    Result:=LazarusHelp;
    exit;
  end;
end;

function TCodeHelpManager.GetModuleOwnerName(TheOwner: TObject): string;
begin
  if TheOwner is TLazPackage then
    Result:=TLazPackage(TheOwner).Name
  else if TheOwner is TLazProject then
    Result:=ExtractFileNameOnly(TLazProject(TheOwner).ProjectInfoFile)
  else if TheOwner=LazarusHelp then
    Result:=IDEProjectName
  else
    Result:='';
end;

function TCodeHelpManager.ExpandFPDocLinkID(const LinkID, DefaultUnitName,
  DefaultOwnerName: string): string;
begin
  Result:=LinkID;
  if (LinkID='') or (LinkID[1]='#') then exit;
  Result:=ExpandFPDocLinkID(LinkId,DefaultUnitName,
                            FindModuleOwner(DefaultOwnerName));
end;

function TCodeHelpManager.ExpandFPDocLinkID(const LinkID,
  DefaultUnitName: string; TheOwner: TObject): string;
  
  function SearchLazDocFile(SearchPath: string;
    const BaseDir, AUnitname: string): string;
  var
    FPDocFilename: String;
  begin
    Result:='';
    if BaseDir='' then exit;
    if not IDEMacros.CreateAbsoluteSearchPath(SearchPath,BaseDir) then exit;
    FPDocFilename:=lowercase(AUnitName)+'.xml';
    Result:=SearchFileInPath(FPDocFilename,'',SearchPath,';',ctsfcDefault);
  end;
  
var
  FirstPointPos: LongInt;
  APackage: TLazPackage;
  FirstIdentifier: String;
  AddUnit: Boolean;
  AProject: TLazProject;
begin
  Result:=LinkID;
  if (LinkID='') or (LinkID[1]='#') then exit;
  FirstPointPos:=System.Pos(LinkID,'.');
  FirstIdentifier:=copy(LinkID,1,FirstPointPos);
  if (FirstIdentifier<>'')
  and (SysUtils.CompareText(FirstIdentifier,DefaultUnitName)<>0) then
  begin
    // the LinkID has sub identifiers, so the first identifier could be a unit
    // But it is not the DefaultUnitName
    // => check if it is another unitname of the Owner
    AddUnit:=false;
    if TheOwner is TLazPackage then begin
      APackage:=TLazPackage(TheOwner);
      if (APackage.FindUnit(FirstIdentifier)=nil) then begin
        // the unit is not owned.
        if SearchLazDocFile(APackage.LazDocPaths,APackage.DirectoryExpanded,
          FirstIdentifier)='' then
        begin
          // and there is no fpdoc file for this identifier
          // => not a unit
          AddUnit:=true;
        end;
      end;
    end else if TheOwner is TLazProject then begin
      AProject:=TLazProject(TheOwner);
      if SearchLazDocFile(AProject.LazDocPaths,
        ExtractFilePath(AProject.ProjectInfoFile),FirstIdentifier)='' then
      begin
        // there is no fpdoc file for this identifier
        // => not a unit
        AddUnit:=true;
      end;
    end else begin
      // unknown owner type
      exit;
    end;
    if AddUnit then
      Result:=DefaultUnitName+'.'+Result;
  end;
  Result:='#'+GetModuleOwnerName(TheOwner)+'.'+Result;
end;

function TCodeHelpManager.CodeNodeToElementName(Tool: TFindDeclarationTool;
  CodeNode: TCodeTreeNode): string;
var
  NodeName: String;
begin
  Result:='';
  if CodeNode.Desc in AllSourceTypes then begin
    Result:=Tool.ExtractSourceName;
  end else begin
    while CodeNode<>nil do begin
      case CodeNode.Desc of
      ctnVarDefinition:
        if Tool.NodeIsResultIdentifier(CodeNode) then
          // fpdoc prefixes the result variable with 'Identifier ' (don't ask)
          NodeName:='Identifier '+Tool.ExtractDefinitionName(CodeNode)
        else
          NodeName:=Tool.ExtractDefinitionName(CodeNode);
      ctnConstDefinition, ctnTypeDefinition, ctnGenericType:
        NodeName:=Tool.ExtractDefinitionName(CodeNode);
      ctnProperty:
        NodeName:=Tool.ExtractPropName(CodeNode,false);
      ctnProcedure:
        if Tool.NodeIsOperator(CodeNode) then
          NodeName:=Tool.ExtractProcHead(CodeNode,
                           [phpWithStart,phpWithResultType,phpWithoutSemicolon])
        else
          NodeName:=Tool.ExtractProcName(CodeNode,[]);
      ctnEnumIdentifier:
        NodeName:=GetIdentifier(@Tool.Src[CodeNode.StartPos]);
      ctnIdentifier:
        if Tool.NodeIsResultType(CodeNode) then
          NodeName:='Result';
      else NodeName:='';
      end;
      if NodeName<>'' then begin
        if Result<>'' then
          Result:='.'+Result;
        Result:=NodeName+Result;
      end;
      CodeNode:=CodeNode.Parent;
    end;
  end;
end;

function TCodeHelpManager.GetFPDocNode(Tool: TCodeTool; CodeNode: TCodeTreeNode;
  Complete: boolean; out FPDocFile: TLazFPDocFile; out DOMNode: TDOMNode;
  out CacheWasUsed: boolean): TCodeHelpParseResult;
var
  SrcFilename: String;
  FPDocFilename: String;
  ElementName: String;
  AnOwner: TObject;
begin
  FPDocFile:=nil;
  DOMNode:=nil;
  CacheWasUsed:=true;
  
  // find corresponding FPDoc file
  SrcFilename:=Tool.MainFilename;
  FPDocFilename:=GetFPDocFilenameForSource(SrcFilename,false,CacheWasUsed,AnOwner);
  if FPDocFilename='' then exit(chprFailed);
  if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

  // load FPDoc file
  Result:=LoadFPDocFile(FPDocFilename,[chofUpdateFromDisk],FPDocFile,CacheWasUsed);
  if Result<>chprSuccess then exit;
  if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

  // find FPDoc node
  ElementName:=CodeNodeToElementName(Tool,CodeNode);
  if ElementName='' then exit(chprFailed);
  DOMNode:=FPDocFile.GetElementWithName(ElementName);
  if DOMNode=nil then exit(chprFailed);
  
  Result:=chprSuccess;
end;

function TCodeHelpManager.GetLinkedFPDocNode(StartFPDocFile: TLazFPDocFile;
  StartDOMNode: TDOMNode; const Path: string; Flags: TCodeHelpOpenFileFlags;
  out ModuleOwner: TObject; out FPDocFile: TLazFPDocFile; out DOMNode: TDOMNode;
  out InvalidPath: integer; out CacheWasUsed: boolean): TCodeHelpParseResult;

  function FindFPDocFilename(BaseDir, SearchPath, AUnitName: string): string;
  begin
    Result:='';
    if not IDEMacros.CreateAbsoluteSearchPath(SearchPath,BaseDir) then exit;
    //DebugLn(['FindFPDocFilename BaseDir=',BaseDir,' SearchPath=',SearchPath,' UnitName=',AUnitname]);
    Result:=SearchFileInPath(AUnitName+'.xml',BaseDir,SearchPath,';',ctsfcDefault);
  end;

  function FindElement(StartPos: integer; aFPDocFile: TLazFPDocFile): boolean;
  var
    ElementName: String;
    p: integer;
  begin
    p:=length(Path)+1;
    while p>StartPos do begin
      ElementName:=copy(Path,StartPos,p-StartPos);
      //DebugLn(['TCodeHelpManager.GetLinkedFPDocNode ElementName=',ElementName]);
      DOMNode:=aFPDocFile.GetElementWithName(ElementName);
      if DOMNode<>nil then begin
        InvalidPath:=p;
        if p>length(Path) then
          GetLinkedFPDocNode:=chprSuccess
        else
          GetLinkedFPDocNode:=chprFailed;
        FPDocFile:=aFPDocFile;
        exit(true);
      end;
      dec(p);
      while (p>StartPos) and (Path[p]<>'.') do dec(p);
    end;
    Result:=false;
  end;

var
  StartPos, p: LongInt;
  PkgName: String;
  Pkg: TLazPackage;
  AUnitName: String;
  AProject: TLazProject;
  FPDocFilename: String;
  BaseDir: String;
begin
  ModuleOwner:=nil;
  FPDocFile:=nil;
  DOMNode:=nil;
  InvalidPath:=0;
  CacheWasUsed:=false;
  Result:=chprFailed;

  //DebugLn(['TCodeHelpManager.GetLinkedFPDocNode Path="',Path,'"']);
  if Path='' then exit;
  if StartDOMNode=nil then ; // for future use

  StartPos:=1;
  p:=1;
  if Path[1]='#' then begin
    // switch package
    while (p<=length(Path)) and (Path[p]<>'.') do inc(p);
    PkgName:=copy(Path,2,p-2);
    //DebugLn(['TCodeHelpManager.GetLinkedFPDocNode PkgName=',PkgName]);
    if PkgName='' then exit;
    Pkg:=PackageGraph.FindAPackageWithName(PkgName,nil);
    if Pkg=nil then exit;
    InvalidPath:=p;
    ModuleOwner:=Pkg;
    if p>length(Path) then begin
      // link to the module, no unit
      Result:=chprSuccess;
      exit;
    end;
    StartPos:=p+1;
    p:=StartPos;
  end else begin
    // relative link (either in the same fpdoc file or of the same module)
    // use same package
    ModuleOwner:=FindModuleOwner(StartFPDocFile);
    if ModuleOwner=nil then exit;
    // try in the same fpdoc file
    if FindElement(StartPos,StartFPDocFile) then exit;
  end;

  // search in another unit
  while (p<=length(Path)) and (Path[p]<>'.') do inc(p);
  AUnitName:=copy(Path,StartPos,p-StartPos);
  //DebugLn(['TCodeHelpManager.GetLinkedFPDocNode UnitName=',AUnitName]);
  if AUnitName='' then exit;
  FPDocFilename:='';
  if ModuleOwner is TLazProject then begin
    AProject:=TLazProject(ModuleOwner);
    if (AProject.LazDocPaths<>'') then begin
      BaseDir:=ExtractFilePath(AProject.ProjectInfoFile);
      FPDocFilename:=FindFPDocFilename(BaseDir,AProject.LazDocPaths,AUnitName);
    end;
  end else if ModuleOwner is TLazPackage then begin
    Pkg:=TLazPackage(ModuleOwner);
    if Pkg.LazDocPaths<>'' then begin
      BaseDir:=Pkg.Directory;
      FPDocFilename:=FindFPDocFilename(BaseDir,Pkg.LazDocPaths,AUnitName);
    end;
  end;
  //DebugLn(['TCodeHelpManager.GetLinkedFPDocNode FPDocFilename=',FPDocFilename]);
  if FPDocFilename='' then exit;

  // load FPDocFile
  Result:=LoadFPDocFile(FPDocFilename,Flags,FPDocFile,CacheWasUsed);
  if Result<>chprSuccess then exit;
  InvalidPath:=p;
  if p>length(Path) then begin
    // link to a unit, no element
    Result:=chprSuccess;
    exit;
  end;
  StartPos:=p+1;

  // find element
  if FindElement(StartPos,FPDocFile) then exit;

  Result:=chprFailed;
end;

function TCodeHelpManager.GetDeclarationChain(Code: TCodeBuffer; X, Y: integer;
  out ListOfPCodeXYPosition: TFPList; out CacheWasUsed: boolean
  ): TCodeHelpParseResult;
begin
  if FDeclarationCache.FindDeclarations(Code,X,Y,ListOfPCodeXYPosition,
    CacheWasUsed)
  then
    Result:=chprSuccess
  else
    Result:=chprFailed;
end;

function TCodeHelpManager.GetCodeContext(CodePos: PCodeXYPosition; out
  FindContext: TFindContext; Complete: boolean; out CacheWasUsed: boolean
  ): TCodeHelpParseResult;
var
  CurTool: TCodeTool;
  CleanPos: integer;
  Node: TCodeTreeNode;
begin
  Result:=chprFailed;
  FindContext:=CleanFindContext;
  CacheWasUsed:=true;

  //DebugLn(['TCodeHelpManager.GetElementChain i=',i,' X=',CodePos^.X,' Y=',CodePos^.Y]);
  if (CodePos=nil) or (CodePos^.Code=nil) or (CodePos^.X<1) or (CodePos^.Y<1)
  then begin
    DebugLn(['TCodeHelpManager.GetElementChain invalid CodePos']);
    exit;
  end;

  // build CodeTree and find node
  if not CodeToolBoss.Explore(CodePos^.Code,CurTool,false,true) then begin
    DebugLn(['TCodeHelpManager.GetElementChain note: there was a parser error']);
  end;
  if CurTool=nil then begin
    DebugLn(['TCodeHelpManager.GetElementChain explore failed']);
    exit;
  end;
  if CurTool.CaretToCleanPos(CodePos^,CleanPos)<>0 then begin
    DebugLn(['TCodeHelpManager.GetElementChain invalid CodePos']);
    exit;
  end;

  Node:=CurTool.FindDeepestNodeAtPos(CleanPos,false);
  if Node=nil then begin
    DebugLn(['TCodeHelpManager.GetElementChain node not found']);
    exit;
  end;

  // use only definition nodes
  if (Node.Desc=ctnProcedureHead) then begin
    if CurTool.PositionInFuncResultName(Node,CleanPos)
    and (Node.LastChild<>nil) and (Node.LastChild.Desc=ctnIdentifier) then begin
      // cursor on function result
      // use the result type node
      Node:=Node.LastChild;
    end else if (Node.Parent<>nil) and (Node.Parent.Desc=ctnProcedure) then
      Node:=Node.Parent;
  end;
  if (not (Node.Desc in
    (AllIdentifierDefinitions+AllSourceTypes
      +[ctnProperty,ctnProcedure,ctnEnumIdentifier])))
  and (not CurTool.NodeIsResultType(Node))
  then begin
    DebugLn(['TCodeHelpManager.GetElementChain ignoring node ',Node.DescAsString]);
    exit;
  end;
  if (CurTool.NodeIsForwardDeclaration(Node)) then begin
    //DebugLn(['TCodeHelpManager.GetElementChain ignoring forward']);
    exit;
  end;
  
  // success
  FindContext.Tool:=CurTool;
  FindContext.Node:=Node;
  Result:=chprSuccess;
end;

function TCodeHelpManager.GetElementChain(Code: TCodeBuffer; X, Y: integer;
  Complete: boolean; out Chain: TCodeHelpElementChain; out CacheWasUsed: boolean
  ): TCodeHelpParseResult;
var
  ListOfPCodeXYPosition: TFPList;
  i: Integer;
  CodePos: PCodeXYPosition;
  CHElement: TCodeHelpElement;
  FPDocFilename: String;
  FindContext: TFindContext;
  AnOwner: TObject;
  NewElementName: String;
  NewUnitName: String;
begin
  Chain:=nil;
  ListOfPCodeXYPosition:=nil;
  CodeToolBoss.ActivateWriteLock;
  try
    //DebugLn(['TCodeHelpManager.GetElementChain GetDeclarationChain...']);
    // get the declaration chain
    Result:=GetDeclarationChain(Code,X,Y,ListOfPCodeXYPosition,CacheWasUsed);
    if Result<>chprSuccess then begin
      {$IFDEF VerboseLazDocFails}
      DebugLn(['TCodeHelpManager.GetElementChain GetDeclarationChain failed ',Code.Filename,' x=',x,' y=',y]);
      {$ENDIF}
      exit;
    end;
    if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

    {$IFDEF VerboseLazDoc}
    DebugLn(['TCodeHelpManager.GetElementChain init the element chain: ListOfPCodeXYPosition.Count=',ListOfPCodeXYPosition.Count,' ...']);
    {$ENDIF}
    // init the element chain
    Result:=chprParsing;
    Chain:=TCodeHelpElementChain.Create;
    Chain.CodePos.Code:=Code;
    Chain.MakeValid;
    Code.LineColToPosition(Y,X,Chain.CodePos.P);
    // fill the element chain
    for i:=0 to ListOfPCodeXYPosition.Count-1 do begin
      // get source position of declaration
      CodePos:=PCodeXYPosition(ListOfPCodeXYPosition[i]);
      Result:=GetCodeContext(CodePos,FindContext,Complete,CacheWasUsed);
      if Result=chprFailed then continue; // skip invalid contexts
      if Result<>chprSuccess then continue;
      if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

      // get fpdoc element path
      NewUnitName:=FindContext.Tool.GetSourceName(false);
      NewElementName:=CodeNodeToElementName(FindContext.Tool,FindContext.Node);

      // skip code nodes with same fpdoc element
      if (Chain.IndexOfElementName(NewUnitName,NewElementName)>=0) then continue;

      // add element
      CHElement:=Chain.Add;
      CHElement.CodeXYPos:=CodePos^;
      CHElement.CodeContext:=FindContext;
      CHElement.ElementName:=NewElementName;
      //DebugLn(['TCodeHelpManager.GetElementChain i=',i,' CodeContext=',FindContextToString(CHElement.CodeContext)]);

      // find corresponding FPDoc file
      CHElement.ElementUnitFileName:=CHElement.CodeContext.Tool.MainFilename;
      CHElement.ElementUnitName:=NewUnitName;
      AnOwner:=Self;
      FPDocFilename:=GetFPDocFilenameForSource(CHElement.ElementUnitFileName,
                                               false,CacheWasUsed,AnOwner);
      CHElement.ElementOwnerName:=GetModuleOwnerName(AnOwner);
      //DebugLn(['TCodeHelpManager.GetElementChain FPDocFilename=',FPDocFilename]);
      if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

      if FPDocFilename<>'' then begin
        // load FPDoc file
        LoadFPDocFile(FPDocFilename,[chofUpdateFromDisk],CHElement.FPDocFile,
                      CacheWasUsed);
        if (not CacheWasUsed) and (not Complete) then exit(chprParsing);
      end;
    end;
    
    // get fpdoc nodes
    for i:=0 to Chain.Count-1 do begin
      CHElement:=Chain[i];
      //DebugLn(['TCodeHelpManager.GetElementChain i=',i,' Element=',CHElement.ElementName]);
      // get fpdoc node
      if (CHElement.FPDocFile<>nil) and (CHElement.ElementName<>'') then begin
        CHElement.ElementNode:=
                  CHElement.FPDocFile.GetElementWithName(CHElement.ElementName);
        CHElement.ElementNodeValid:=true;
      end;
      //DebugLn(['TCodeHelpManager.GetElementChain ElementNode=',CHElement.ElementNode<>nil]);
    end;

    Result:=chprSuccess;
  finally
    if Result<>chprSuccess then
      FreeAndNil(Chain);
    CodeToolBoss.DeactivateWriteLock;
  end;
end;

function TCodeHelpManager.GetHTMLHint(Code: TCodeBuffer; X, Y: integer;
  Options: TCodeHelpHintOptions; out BaseURL, HTMLHint: string; out CacheWasUsed: boolean
  ): TCodeHelpParseResult;
const
  le = '<BR>'+LineEnding;
var
  IsHTML: boolean;
  
  function EndNow(var LastResult: TCodeHelpParseResult): boolean;
  begin
    if LastResult<>chprSuccess then
    begin
      Result:=true;
      if HTMLHint<>'' then
        LastResult:=chprSuccess
      else
        LastResult:=chprFailed;
      exit;
    end;
    if (not CacheWasUsed) and (chhoSmallStep in Options) then
    begin
      Result:=true;
      LastResult:=chprParsing;
    end;
    Result:=false;
  end;
  
  procedure AddText(const s: string);
  begin
    if IsHTML then
      HTMLHint:=HTMLHint+le+le+TextToHTML(s)
    else begin
      if HTMLHint<>'' then
        HTMLHint:=HTMLHint+LineEnding+LineEnding;
      HTMLHint:=HTMLHint+s;
    end;
  end;

  procedure AddHTML(const s: string);
  begin
    if not IsHTML then begin
      IsHTML:=true;
      if HTMLHint<>'' then
        HTMLHint:=TextToHTML(HTMLHint)+le;
    end;
    if HTMLHint<>'' then
      HTMLHint:=HTMLHint+le;
    HTMLHint:=HTMLHint+s;
  end;
  
var
  Chain: TCodeHelpElementChain;
  i: Integer;
  Item: TCodeHelpElement;
  NodeValues: TFPDocElementValues;
  ListOfPCodeXYPosition: TFPList;
  CodeXYPos: PCodeXYPosition;
  CommentStart: integer;
  NestedComments: Boolean;
  CommentStr: String;
  ItemAdded: Boolean;
  CommentCode: TCodeBuffer;
  j: Integer;
  {$ifdef VerboseHints}
  f: TFPDocItem;
  {$endif}
begin
  {$IFDEF EnableNewCodeHints}
  Result:=GetHTMLHint2(Code,X,Y,Options,BaseURL,HTMLHint,CacheWasUsed);
  exit;
  {$ENDIF}
  {$ifdef VerboseHints}
    DebugLn(['TCodeHelpManager.GetHint ',Code.Filename,' ',X,',',Y]);
  {$endif}
  BaseURL:='lazdoc://';
  IsHTML:=false;
  CodeToolBoss.ActivateWriteLock;
  try
    if chhoDeclarationHeader in Options then
      HTMLHint := CodeToolBoss.FindSmartHint(Code,X,Y)
    else
      HTMLHint := '';

    CacheWasUsed:=true;
    Chain:=nil;
    ListOfPCodeXYPosition:=nil;
    try
      {$ifdef VerboseHints}
      DebugLn(['TCodeHelpManager.GetHint GetElementChain...']);
      {$endif}
      Result := GetElementChain(Code, X, Y, not (chhoSmallStep in Options), Chain, CacheWasUsed);
      if EndNow(Result) then exit;

      if Chain <> nil then
      begin
        for i := 0 to Chain.Count - 1 do
        begin
          Item:=Chain[i];
          ItemAdded:=false;
          {$ifdef VerboseHints}
          DebugLn(['TCodeHelpManager.GetHint ',i,' Element=',Item.ElementName]);
          {$endif}
          if Item.ElementNode<>nil then
          begin
            NodeValues:=Item.FPDocFile.GetValuesFromNode(Item.ElementNode);
            {$ifdef VerboseHints}
            for f:=Low(TFPDocItem) to High(TFPDocItem) do
              DebugLn(['TCodeHelpManager.GetHint ',FPDocItemNames[f],' ',NodeValues[f]]);
            {$endif}
            if NodeValues[fpdiShort]<>'' then
            begin
              AddHTML('<B>' + Item.ElementName + '</B>' + le + NodeValues[fpdiShort]);
              ItemAdded:=true;
            end;
          end;

          // Add comments
          if not (chhoNoComments in Options) then
          begin
            FreeListOfPCodeXYPosition(ListOfPCodeXYPosition);
            if CodeToolBoss.GetPasDocComments(Item.CodeXYPos.Code,
               Item.CodeXYPos.X, Item.CodeXYPos.Y, ListOfPCodeXYPosition) and
               (ListOfPCodeXYPosition<>nil) then
            begin
              NestedComments := CodeToolBoss.GetNestedCommentsFlagForFile(
                                                      Item.CodeXYPos.Code.Filename);
              for j := 0 to ListOfPCodeXYPosition.Count - 1 do
              begin
                CodeXYPos := PCodeXYPosition(ListOfPCodeXYPosition[j]);
                CommentCode := CodeXYPos^.Code;
                CommentCode.LineColToPosition(CodeXYPos^.Y,CodeXYPos^.X,CommentStart);
                if (CommentStart<1) or (CommentStart>CommentCode.SourceLength)
                then
                  continue;
                CommentStr:=ExtractCommentContent(CommentCode.Source,CommentStart,
                                                  NestedComments,true,true,true);
                if CommentStr <> '' then
                begin
                  if not ItemAdded then
                  begin
                    AddText(Item.ElementName+LineEnding
                            +CommentStr);
                  end else
                  begin
                    AddText(CommentStr);
                  end;
                  ItemAdded := true;
                end;
              end;
            end;
          end;
        end;
      end;
      Result:=chprSuccess;
    finally
      FreeListOfPCodeXYPosition(ListOfPCodeXYPosition);
      Chain.Free;
    end;
  finally
    CodeToolBoss.DeactivateWriteLock;
    if IsHTML then
      HTMLHint:='<HTML><BODY>'+HTMLHint+'</BODY></HTML>';
  end;
  {$ifdef VerboseHints}
  DebugLn(['TCodeHelpManager.GetHint END Hint="',HTMLHint,'"']);
  {$endif}
end;

function TCodeHelpManager.GetHTMLHint2(Code: TCodeBuffer; X, Y: integer;
  Options: TCodeHelpHintOptions; out BaseURL, HTMLHint: string;
  out CacheWasUsed: boolean): TCodeHelpParseResult;
var
  CursorPos: TCodeXYPosition;
  CTTool: TFindDeclarationTool;
  CTNode: TCodeTreeNode;
  XYPos: TCodeXYPosition;
  aTopLine: integer;
  CTHint: String;
  ListOfPCodeXYPosition: TFPList;
  ElementName: String;
  AnOwner: TObject;
  FPDocFilename: String;
  FPDocFile: TLazFPDocFile;
  Complete: boolean;
  ElementNode: TDOMNode;
  ElementNames: TStringList;
  i: Integer;
  OldXYPos: TCodeXYPosition;
  OldCTTool: TFindDeclarationTool;
  OldCTNode: TCodeTreeNode;
  n: Integer;
  LastOwner: TObject;
  s: String;

  procedure AddLinkToOwner(CurOwner: TObject);
  var
    s: String;
  begin
    if (CurOwner=nil) or (CurOwner=LastOwner) then exit;
    s:=OwnerToFPDocHint(CurOwner);
    if s='' then exit;
    HTMLHint:=HTMLHint+s+'<br>'+LineEnding;
    LastOwner:=AnOwner;
  end;

begin
  Result:=chprFailed;
  BaseURL:='lazdoc://';
  HTMLHint:='';
  CacheWasUsed:=true;

  CursorPos.X:=X;
  CursorPos.Y:=Y;
  CursorPos.Code:=Code;
  ListOfPCodeXYPosition:=nil;
  Complete:=not (chhoSmallStep in Options);
  ElementNames:=TStringList.Create;
  try
    if not CodeToolBoss.InitCurCodeTool(Code) then exit;
    try
      // find declaration
      if not CodeToolBoss.CurCodeTool.FindDeclaration(CursorPos,
        DefaultFindSmartHintFlags,CTTool,CTNode,XYPos,aTopLine)
      then
        exit;

      if chhoDeclarationHeader in Options then begin
        HTMLHint:=HTMLHint+'<div class="header">';
        // add declaration
        CTHint:=CTTool.GetSmartHint(CTNode,XYPos,false);
        HTMLHint:=HTMLHint+'  '+SourceToFPDocHint(CTHint);

        // add link to declaration
        HTMLHint:=HTMLHint+'<br>'+LineEnding;
        if XYPos.Code=nil then
          CTTool.CleanPosToCaret(CTNode.StartPos,XYPos);
        HTMLHint:=HTMLHint+'  '+SourcePosToFPDocHint(XYPos)+LineEnding;
        HTMLHint:=HTMLHint+'</div>'+LineEnding;
      end;

      LastOwner:=nil;
      for n:=1 to 30 do begin
        ElementName:=CodeNodeToElementName(CTTool,CTNode);
        i:=ElementNames.Count-1;
        while (i>=0) and (ElementNames.Objects[i]<>CTTool)
        and (SysUtils.CompareText(ElementNames[i],ElementName)<>0) do
          dec(i);
        if i>=0 then begin
          // a loop or a forward definition
        end else begin
          ElementNames.AddObject(ElementName,CTTool);

          // add fpdoc entry
          FPDocFilename:=GetFPDocFilenameForSource(CTTool.MainFilename,
                                                   false,CacheWasUsed,AnOwner);
          //DebugLn(['TCodeHelpManager.GetHTMLHint2 FPDocFilename=',FPDocFilename,' ElementName="',ElementName,'"']);
          if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

          if n=1 then
            AddLinkToOwner(AnOwner); // add link to owner of declaration, even if there is no fpdoc entry

          if FPDocFilename<>'' then begin
            // load FPDoc file
            LoadFPDocFile(FPDocFilename,[chofUpdateFromDisk],FPDocFile,CacheWasUsed);
            if (not CacheWasUsed) and (not Complete) then exit(chprParsing);

            ElementNode:=FPDocFile.GetElementWithName(ElementName);
            if ElementNode<>nil then begin
              //debugln(['TCodeHelpManager.GetHTMLHint2 fpdoc element found "',ElementName,'"']);
              AddLinkToOwner(AnOwner);

              s:=AppendLineEnding(GetFPDocNodeAsHTML(FPDocFile,ElementNode.FindNode(FPDocItemNames[fpdiShort])));
              s:=s+AppendLineEnding(GetFPDocNodeAsHTML(FPDocFile,ElementNode.FindNode(FPDocItemNames[fpdiDescription])));
              if s<>'' then begin
                s:='<br>'+LineEnding
                   +'<div class="title">Description</div>'+LineEnding+s;
                HTMLHint:=HTMLHint+s;
              end;
              HTMLHint:=HTMLHint+GetFPDocNodeAsHTML(FPDocFile,ElementNode.FindNode(FPDocItemNames[fpdiErrors]));
              // todo HTMLHint:=HTMLHint+GetFPDocNodeAsHTML(FPDocFile,ElementNode.FindNode(FPDocItemNames[fpdiSeeAlso]));
              HTMLHint:=HTMLHint+GetFPDocNodeAsHTML(FPDocFile,ElementNode.FindNode(FPDocItemNames[fpdiExample]));
            end;
          end;

          if not (chhoNoComments in Options) then
          begin
            // add pasdoc
            HTMLHint:=HTMLHint+GetPasDocCommentsAsHTML(CTTool,CTNode);
          end;
        end;

        // find inherited node
        if (CTNode.Desc=ctnProperty)
        or ((CTNode.Desc in [ctnProcedure,ctnProcedureHead])
            and (CTTool.ProcNodeHasSpecifier(CTNode,psOVERRIDE)))
        then begin
          debugln(['TCodeHelpManager.GetHTMLHint2 searching for inherited of ',CTNode.DescAsString,' ',dbgs(XYPos)]);
          OldXYPos:=XYPos;
          OldCTTool:=CTTool;
          OldCTNode:=CTNode;
          if (not OldCTTool.FindDeclaration(OldXYPos,[fsfSearchSourceName],
            CTTool,CTNode,XYPos,aTopLine))
          or (CTNode=OldCTNode)
          then begin
            debugln(['TCodeHelpManager.GetHTMLHint2 inherited not found: ',dbgs(OldXYPos)]);
            break;
          end;
        end else begin
          debugln(['TCodeHelpManager.GetHTMLHint2 not searching inherited for ',CTNode.DescAsString]);
          break;
        end;

      end;
    except
      on E: Exception do begin
        debugln(['TCodeHelpManager.GetHTMLHint2 Exception: ',E.Message]);
        DumpExceptionBackTrace;
      end;
    end;

  finally
    ElementNames.Free;
    FreeListOfPCodeXYPosition(ListOfPCodeXYPosition);
    HTMLHint:='<html><head><link rel="stylesheet" href="lazdoc://lazarus/lazdoc.css" type="text/css"></head>'+LineEnding
      +'<body>'+LineEnding+HTMLHint+'</body>'+LineEnding;
  end;
  debugln(['TCodeHelpManager.GetHTMLHint2 ',HTMLHint]);
  Result:=chprSuccess;
end;

function TCodeHelpManager.GetPasDocCommentsAsHTML(Tool: TFindDeclarationTool;
  Node: TCodeTreeNode): string;
var
  ListOfPCodeXYPosition: TFPList;
  i: Integer;
  CodeXYPos: PCodeXYPosition;
  CommentCode: TCodeBuffer;
  CommentStart: integer;
  NestedComments: Boolean;
  CommentStr: String;
begin
  Result:='';
  if (Tool=nil) or (Node=nil) then exit;
  ListOfPCodeXYPosition:=nil;
  try
    if not Tool.GetPasDocComments(Node,ListOfPCodeXYPosition) then exit;
    if ListOfPCodeXYPosition=nil then exit;
    NestedComments := Tool.Scanner.NestedComments;
    for i := 0 to ListOfPCodeXYPosition.Count - 1 do
    begin
      CodeXYPos := PCodeXYPosition(ListOfPCodeXYPosition[i]);
      CommentCode := CodeXYPos^.Code;
      CommentCode.LineColToPosition(CodeXYPos^.Y,CodeXYPos^.X,CommentStart);
      if (CommentStart<1) or (CommentStart>CommentCode.SourceLength)
      then
        continue;
      CommentStr:=ExtractCommentContent(CommentCode.Source,CommentStart,
                                        NestedComments,true,true,true);
      if CommentStr <> '' then
        Result:=Result+'<span class="comment">'+TextToHTML(CommentStr)
          +' ('+SourcePosToFPDocHint(CodeXYPos^,'Source')+')'
          +'</span><br>'+LineEnding;
    end;

  finally
    FreeListOfPCodeXYPosition(ListOfPCodeXYPosition);
  end;
end;

function TCodeHelpManager.GetFPDocNodeAsHTML(FPDocFile: TLazFPDocFile;
  DOMNode: TDOMNode): string;

  function NodeToHTML(Node: TDOMNode): string; forward;

  function AddChilds(Node: TDOMNode): string;
  var
    Child: TDOMNode;
  begin
    Result:='';
    Child:=Node.FirstChild;
    while Child<>nil do begin
      Result:=Result+NodeToHTML(Child);
      Child:=Child.NextSibling;
    end;
  end;

  function NodeToHTML(Node: TDOMNode): string;
  var
    s: String;
    Attr: TDOMNode;
  begin
    Result:='';
    if Node=nil then exit;
    //debugln(['TCodeHelpManager.GetFPDocNodeAsHTML.NodeToHTML ',Node.NodeName]);
    if (Node.NodeName='short')
    or (Node.NodeName='descr')
    or (Node.NodeName='seealso')
    or (Node.NodeName='errors')
    then begin
      s:=AddChilds(Node);
      if s='' then exit;
      if Node.NodeName='errors' then
        Result:=Result+'<div class="title">'+'Errors'+'</div>'
      else if Node.NodeName='seealso' then
        Result:=Result+'<div class="title">'+'See also'+'</div>';
      Result:=Result+'<div class="'+Node.NodeName+'">'+s+'</div>'+LineEnding;
    end else if (Node.NodeName='p') or (Node.NodeName='b')
    then begin
      Result:=Result+'<'+Node.NodeName+'>'+AddChilds(Node)+'</'+Node.NodeName+'>';
    end else if (Node.NodeName='var') then begin
      Result:=Result+'<span class="keyword">'+AddChilds(Node)+'</span>';
    end else if (Node.NodeName='link') and (Node.Attributes<>nil) then begin
      Attr:=Node.Attributes.GetNamedItem('id');
      if (Attr=nil) or (Attr.NodeValue='') then exit;
      s:=AddChilds(Node);
      if s='' then s:=Attr.NodeValue;
      Result:=Result+'<a href="'+Attr.NodeValue+'">'+s+'</a><br>';
    end else if (Node.NodeName='example') then begin
      Attr:=Node.Attributes.GetNamedItem('file');
      if (Attr=nil) or (Attr.NodeValue='') then exit;
      s:=ExtractFilePath(FPDocFile.Filename);
      if not FilenameIsAbsolute(s) then exit;
      s:=s+Attr.NodeValue;
      Result:=Result+SourcePosToFPDocHint(s,1,1,'Example')+'<br>';
    end else if (Node.NodeName='#text') then begin
      Result:=Result+Node.NodeValue;
    end else begin
      debugln(['TCodeHelpManager.GetFPDocNodeAsHTML.NodeToHTML skipping ',Node.NodeName]);
    end;
  end;

begin
  Result:=NodeToHTML(DOMNode);
end;

function TCodeHelpManager.TextToHTML(Txt: string): string;
var
  p: Integer;
begin
  Result:=Txt;
  p:=length(Result);
  while p>0 do
  begin
    case Result[p] of
    '<': Result:=copy(Result,1,p-1)+'&lt;'+copy(Result,p+1,length(Result));
    '>': Result:=copy(Result,1,p-1)+'&gt;'+copy(Result,p+1,length(Result));
    '&': Result:=copy(Result,1,p-1)+'&amp;'+copy(Result,p+1,length(Result));
    #10,#13:
      begin
        if (p>1) and (Result[p-1] in [#10,#13]) and (Result[p-1]<>Result[p]) then
          dec(p);
        Result:=copy(Result,1,p-1)+'<br>'+copy(Result,p,length(Result));
      end;
    end;
    dec(p);
  end;
end;

function TCodeHelpManager.CreateElement(Code: TCodeBuffer; X, Y: integer;
  out Element: TCodeHelpElement): Boolean;
var
  CacheWasUsed: boolean;
  FPDocFilename: String;
  AnOwner: TObject;
  CHResult: TCodeHelpParseResult;
begin
  Result:=false;
  Element:=nil;
  if Code=nil then begin
    DebugLn(['TCodeHelpManager.CreateElement failed Code=nil']);
    exit;
  end;
  DebugLn(['TCodeHelpManager.CreateElement START ',Code.Filename,' ',X,',',Y]);
  
  Element:=TCodeHelpElement.Create;
  try
    // check if code context can have a fpdoc element
    Element.CodeXYPos.Code:=Code;
    Element.CodeXYPos.X:=X;
    Element.CodeXYPos.Y:=Y;
    if GetCodeContext(@Element.CodeXYPos,Element.CodeContext,true,
      CacheWasUsed)<>chprSuccess then
    begin
      DebugLn(['TCodeHelpManager.CreateElement GetCodeContext failed for ',Code.Filename,' ',X,',',Y]);
      exit;
    end;
    Element.ElementName:=CodeNodeToElementName(Element.CodeContext.Tool,
                                               Element.CodeContext.Node);
    DebugLn(['TCodeHelpManager.CreateElement Element.ElementName=',Element.ElementName]);

    // find / create fpdoc file
    Element.ElementUnitFileName:=Element.CodeContext.Tool.MainFilename;
    Element.ElementUnitName:=Element.CodeContext.Tool.GetSourceName(false);
    FPDocFilename:=GetFPDocFilenameForSource(Element.ElementUnitFileName,false,
                                             CacheWasUsed,AnOwner,true);
    if FPDocFilename='' then begin
      // no fpdoc file
      DebugLn(['TCodeHelpManager.CreateElement unable to create fpdoc file for ',FPDocFilename]);
    end;
    DebugLn(['TCodeHelpManager.CreateElement FPDocFilename=',FPDocFilename]);

    // parse fpdoc file
    CHResult:=LoadFPDocFile(FPDocFilename,[chofUpdateFromDisk],
                            Element.FPDocFile,CacheWasUsed);
    if CHResult<>chprSuccess then begin
      DebugLn(['TCodeHelpManager.CreateElement unable to load fpdoc file ',FPDocFilename]);
      exit;
    end;

    Element.ElementNode:=Element.FPDocFile.GetElementWithName(
                                                      Element.ElementName,true);
    Result:=Element.ElementNode<>nil;
  finally
    if not Result then
      FreeAndNil(Element);
  end;
end;

function TCodeHelpManager.SourceToFPDocHint(Src: string; NestedComments: boolean
  ): string;

  procedure EndSpan(SpanName: string; var r: string);
  begin
    if SpanName='' then exit;
    r:=r+'</span>';
  end;

  procedure StartSpan(SpanName: string; var r: string);
  begin
    if SpanName='' then exit;
    r:=r+'<span class="'+SpanName+'">';
  end;

  function TokenIDToSpan(TokenID: TtkTokenKind): string;
  begin
    case TokenID of
    tkComment: Result:='comment';
    tkIdentifier: Result:='identifer';
    tkKey: Result:='keyword';
    tkNumber: Result:='number';
    tkString: Result:='string';
    tkSymbol: Result:='symbol';
    tkDirective: Result:='directive';
    else Result:='';
    end;
  end;

var
  TokenID: TtkTokenKind;
  LastTokenID: TtkTokenKind;
  Token: String;
begin
  Result:='';
  PasHighlighter.NestedComments:=NestedComments;
  PasHighlighter.ResetRange;
  PasHighlighter.SetLine(Src,0);
  LastTokenID:=tkUnknown;
  while not PasHighlighter.GetEol do begin
    TokenID:=PasHighlighter.GetTokenID;
    if (Result<>'') and (LastTokenID<>TokenID) then
      EndSpan(TokenIDToSpan(LastTokenID),Result);
    if (Result='') or (LastTokenID<>TokenID) then
      StartSpan(TokenIDToSpan(TokenID),Result);
    Token:=PasHighlighter.GetToken;
    //debugln(['TCodeHelpManager.SourceToFPDocHint ',Token,' ',ord(TokenID)]);
    Result:=Result+TextToHTML(Token);
    LastTokenID:=TokenID;
    PasHighlighter.Next;
  end;
  if (Result<>'') and (LastTokenID<>tkUnknown) then
    EndSpan(TokenIDToSpan(LastTokenID),Result);
end;

function TCodeHelpManager.SourcePosToFPDocHint(XYPos: TCodeXYPosition;
  Caption: string): string;
begin
  Result:='';
  if XYPos.Code=nil then exit;
  Result:=SourcePosToFPDocHint(XYPos.Code.Filename,XYPos.X,XYPos.Y,Caption);
end;

function TCodeHelpManager.SourcePosToFPDocHint(const aFilename: string; X,
  Y: integer; Caption: string): string;
var
  Link: String;
  i: Integer;
begin
  Result:='';
  if aFilename='' then exit;
  Link:=aFilename;
  if Y>=1 then begin
    Link:=Link+'('+IntToStr(Y);
    if X>=1 then
      Link:=Link+','+IntToStr(X);
    Link:=Link+')';
  end;
  if Caption='' then begin
    Caption:=Link;
    // make caption breakable into several lines
    for i:=length(Caption)-1 downto 1 do begin
      if Caption[i]=PathDelim then
        System.Insert('<wbr/>',Caption,i+1);
    end;
  end;
  Result:='<a href="source://'+Link+'">'+Caption+'</a>';
end;

function TCodeHelpManager.OwnerToFPDocHint(AnOwner: TObject): string;
begin
  Result:='';
  if AnOwner=nil then exit;
  if AnOwner is TLazPackage then
    Result:='<span class="seealso">Package <a href="openpackage://'+TLazPackage(AnOwner).Name+'">'
                                   +TLazPackage(AnOwner).Name+'</a></span>';
end;

procedure TCodeHelpManager.FreeDocs;
var
  AVLNode: TAvgLvlTreeNode;
begin
  AVLNode:=FDocs.FindLowest;
  while AVLNode<>nil do begin
    CallDocChangeEvents(chmhDocChanging,TLazFPDocFile(AVLNode.Data));
    AVLNode:=FDocs.FindSuccessor(AVLNode);
  end;
  FDocs.FreeAndClear;
end;

procedure TCodeHelpManager.ClearSrcToDocMap;
begin
  FSrcToDocMap.FreeAndClear;
end;

procedure TCodeHelpManager.RemoveAllHandlersOfObject(AnObject: TObject);
var
  HandlerType: TCodeHelpManagerHandler;
begin
  for HandlerType:=Low(TCodeHelpManagerHandler) to High(TCodeHelpManagerHandler) do
    FHandlers[HandlerType].RemoveAllMethodsOfObject(AnObject);
end;

procedure TCodeHelpManager.AddHandlerOnChanging(
  const OnDocChangingEvent: TCodeHelpChangeEvent; AsLast: boolean);
begin
  AddHandler(chmhDocChanging,TMethod(OnDocChangingEvent),AsLast);
end;

procedure TCodeHelpManager.RemoveHandlerOnChanging(
  const OnDocChangingEvent: TCodeHelpChangeEvent);
begin
  RemoveHandler(chmhDocChanging,TMethod(OnDocChangingEvent));
end;

procedure TCodeHelpManager.AddHandlerOnChanged(
  const OnDocChangedEvent: TCodeHelpChangeEvent; AsLast: boolean);
begin
  AddHandler(chmhDocChanged,TMethod(OnDocChangedEvent),AsLast);
end;

procedure TCodeHelpManager.RemoveHandlerOnChanged(
  const OnDocChangedEvent: TCodeHelpChangeEvent);
begin
  RemoveHandler(chmhDocChanged,TMethod(OnDocChangedEvent));
end;


{ TCodeHelpElementChain }

function TCodeHelpElementChain.GetCount: integer;
begin
  Result:=FItems.Count;
end;

function TCodeHelpElementChain.GetItems(Index: integer): TCodeHelpElement;
begin
  Result:=TCodeHelpElement(FItems[Index]);
end;

function TCodeHelpElementChain.Add: TCodeHelpElement;
begin
  Result:=TCodeHelpElement.Create;
  FItems.Add(Result);
end;

constructor TCodeHelpElementChain.Create;
begin
  FItems:=TFPList.Create;
end;

destructor TCodeHelpElementChain.Destroy;
begin
  Clear;
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TCodeHelpElementChain.Clear;
var
  i: Integer;
begin
  for i:=0 to FItems.Count-1 do TObject(FItems[i]).Free;
  FItems.Clear;
end;

function TCodeHelpElementChain.IndexOfFile(AFile: TLazFPDocFile): integer;
begin
  Result:=FItems.Count-1;
  while (Result>=0) do begin
    if Items[Result].FPDocFile=AFile then exit;
    dec(Result);
  end;
end;

function TCodeHelpElementChain.IndexOfElementName(ElementName: string): integer;
begin
  Result:=FItems.Count-1;
  while (Result>=0) do begin
    if SysUtils.CompareText(Items[Result].ElementName,ElementName)=0 then exit;
    dec(Result);
  end;
end;

function TCodeHelpElementChain.IndexOfElementName(ElementUnitName,
  ElementName: string): integer;
begin
  Result:=FItems.Count-1;
  while (Result>=0) do begin
    if (SysUtils.CompareText(Items[Result].ElementUnitName,ElementUnitName)=0)
    and (SysUtils.CompareText(Items[Result].ElementName,ElementName)=0) then
      exit;
    dec(Result);
  end;
end;

function TCodeHelpElementChain.IsValid: boolean;
begin
  Result:=(IDEChangeStep=CompilerParseStamp)
    and (CodetoolsChangeStep=CodeToolBoss.CodeTreeNodesDeletedStep);
  //DebugLn(['TCodeHelpElementChain.IsValid Result=',Result,' IDEChangeStep=',IDEChangeStep,' CompilerParseStamp=',CompilerParseStamp,' CodetoolsChangeStep=',CodetoolsChangeStep,' CodeToolBoss.CodeTreeNodesDeletedStep=',CodeToolBoss.CodeTreeNodesDeletedStep]);
end;

procedure TCodeHelpElementChain.MakeValid;
begin
  IDEChangeStep:=CompilerParseStamp;
  CodetoolsChangeStep:=CodeToolBoss.CodeTreeNodesDeletedStep;
end;

function TCodeHelpElementChain.DocFile: TLazFPDocFile;
begin
  Result:=nil;
  if (Count>0) then
    Result:=Items[0].FPDocFile;
end;

procedure TCodeHelpElementChain.WriteDebugReport;
var
  Line, Column: integer;
  i: Integer;
begin
  CodePos.Code.AbsoluteToLineCol(CodePos.P,Line,Column);
  DebugLn(['TCodeHelpElementChain.WriteDebugReport ',CodePos.Code.Filename,' X=',Column,' Y=',Line,' IDEChangeStep=',IDEChangeStep,' CodetoolsChangeStep=',CodetoolsChangeStep]);
  for i:=0 to Count-1 do
    Items[i].WriteDebugReport;
end;

{ TLazFPDocNode }

constructor TLazFPDocNode.Create(AFile: TLazFPDocFile; ANode: TDOMNode);
begin
  Node:=ANode;
  DocFile:=AFile;
end;

{ TCodeHelpElement }

procedure TCodeHelpElement.WriteDebugReport;
begin
  DebugLn(['  ',CodeXYPos.Code.Filename,' X=',CodeXYPos.X,' Y=',CodeXYPos.Y,' ElementOwnerName=',ElementOwnerName,' ElementUnitName=',ElementUnitName,' ElementUnitFileName=',ElementUnitFileName,' ElementName=',ElementName]);
end;

end.

