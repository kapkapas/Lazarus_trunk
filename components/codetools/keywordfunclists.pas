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
    A TKeyWordFunctionList is a list of TKeyWordFunctionListItem.
}
unit KeywordFuncLists;

{$ifdef FPC}{$mode objfpc}{$endif}{$H+}

interface

{ $DEFINE MEM_CHECK}

uses
  {$IFDEF MEM_CHECK}
  MemCheck,
  {$ENDIF}
  Classes, SysUtils, FileProcs;

type
  TKeyWordFunction = function: boolean of object;
  TKeyWordDataFunction = function(Data: Pointer): boolean of object;

  TKeyWordFunctionListItem = record
    IsLast: boolean;
    KeyWord: shortstring;
    DoIt: TKeyWordFunction;
    DoDataFunction: TKeyWordDataFunction;
  end;
  PKeyWordFunctionListItem = ^TKeyWordFunctionListItem;

  TKeyWordFunctionList = class
  private
    FItems: PKeyWordFunctionListItem;
    FCount: integer;
    FCapacity: integer;
    FSorted: boolean;
    FBucketStart: {$ifdef FPC}^{$else}array of {$endif}integer;
    FMaxHashIndex: integer;
    function KeyWordToHashIndex(const AKeyWord: shortstring): integer;
    function KeyWordToHashIndex(const ASource: string;
       AStart, ALen: integer): integer;
    function KeyWordToHashIndex(Identifier: PChar): integer;
    function KeyWordToHashIndex(Start: PChar; Len: integer): integer;
  public
    DefaultKeyWordFunction: TKeyWordFunction;
    function DoIt(const AKeyWord: shortstring): boolean;
    function DoIt(const ASource: string;
       KeyWordStart, KeyWordLen: integer): boolean;
    function DoIt(Identifier: PChar): boolean;
    function DoItUppercase(const AnUpperSource: string;
       KeyWordStart, KeyWordLen: integer): boolean;
    function DoItCaseInsensitive(const AKeyWord: shortstring): boolean;
    function DoDataFunction(Start: PChar; Len: integer; Data: pointer): boolean;
    procedure Clear;
    procedure Add(const AKeyWord: shortstring;
                  const AFunction: TKeyWordFunction);
    procedure AddExtended(const AKeyWord: shortstring;
                          const AFunction: TKeyWordFunction;
                          const ADataFunction: TKeyWordDataFunction);
    procedure Add(List: TKeyWordFunctionList);
    procedure Sort;
    property Sorted: boolean read FSorted;
    procedure WriteDebugListing;
    function AllwaysTrue: boolean;
    function AllwaysFalse: boolean;
    function Count: integer;
    function GetItem(Index: integer): TKeyWordFunctionListItem;
    function IndexOf(const AKeyWord: shortstring): integer;
    constructor Create;
    destructor Destroy;  override;
  end;

var
  IsKeyWordMethodSpecifier,
  IsKeyWordProcedureSpecifier,
  IsKeyWordProcedureTypeSpecifier,
  IsKeyWordProcedureBracketSpecifier,
  IsKeyWordSection,
  IsKeyWordInConstAllowed,
  WordIsKeyWord,
  WordIsDelphiKeyWord,
  IsWordBuiltInFunc,
  WordIsTermOperator,
  WordIsPropertySpecifier,
  WordIsBlockKeyWord,
  EndKeyWordFuncList,
  PackedTypesKeyWordFuncList,
  GenericTypesKeyWordFuncList,
  BlockStatementStartKeyWordFuncList,
  WordIsLogicalBlockStart,
  WordIsLogicalBlockEnd,
  WordIsLogicalBlockMiddle,
  WordIsBlockStatementStart,
  WordIsBlockStatementEnd,
  WordIsBlockStatementMiddle,
  WordIsBinaryOperator,
  WordIsLvl1Operator, WordIsLvl2Operator, WordIsLvl3Operator, WordIsLvl4Operator,
  WordIsBooleanOperator,
  WordIsOrdNumberOperator,
  WordIsNumberOperator,
  WordIsPredefinedFPCIdentifier,
  WordIsPredefinedDelphiIdentifier,
  UnexpectedKeyWordInBeginBlock,
  UnexpectedKeyWordInAsmBlock: TKeyWordFunctionList;
  UpChars: array[char] of char;

function UpperCaseStr(const s: string): string;
function IsUpperCaseStr(const s: string): boolean;

implementation


var
  CharToHash: array[char] of integer;
  IsIdentChar: array[char] of boolean;
  UpWords: array[word] of word;

function UpperCaseStr(const s: string): string;
var i, l, l2: integer;
  pSrc, pDest: PWord;
begin
  l:=length(s);
  SetLength(Result,l);
  if l>0 then begin
    pDest:=@Result[1];
    pSrc:=@s[1];
    l2:=(l shr 1)-1;
    for i:=0 to l2 do
      pDest[i]:=UpWords[pSrc[i]];
    if odd(l) then
      Result[l]:=UpChars[s[l]];
  end;
end;

function IsUpperCaseStr(const s: string): boolean;
var i, l: integer;
begin
  l:=length(s);
  i:=1;
  while (i<=l) and (UpChars[s[i]]=s[i]) do inc(i);
  Result:=i>l;
end;

{ TKeyWordFunctionList }

constructor TKeyWordFunctionList.Create;
begin
  inherited Create;
  FItems:=nil;
  FCount:=0;
  FCapacity:=0;
  FSorted:=true;
  FBucketStart:=nil;
  FMaxHashIndex:=-1;
  DefaultKeyWordFunction:={$ifdef FPC}@{$endif}AllwaysFalse;
end;

destructor TKeyWordFunctionList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TKeyWordFunctionList.Clear;
begin
  if FItems<>nil then begin
    FreeMem(FItems);
    FItems:=nil;
  end;
  FCount:=0;
  FCapacity:=0;
  if FBucketStart<>nil then begin
    FreeMem(FBucketStart);
    FBucketStart:=nil;
  end;
  FMaxHashIndex:=-1;  
  FSorted:=true;
end;

function TKeyWordFunctionList.KeyWordToHashIndex(
  const AKeyWord: shortstring): integer;
var KeyWordLen, i: integer;
begin
  KeyWordLen:=length(AKeyWord);
  if KeyWordLen>20 then KeyWordLen:=20;
  Result:=0;
  for i:=1 to KeyWordLen do
    inc(Result,CharToHash[AKeyWord[i]]);
  if Result>FMaxHashIndex then Result:=-1;
end;

function TKeyWordFunctionList.KeyWordToHashIndex(const ASource: string;
  AStart, ALen: integer): integer;
var i, AEnd: integer;
begin
  if ALen>20 then ALen:=20;
  AEnd:=AStart+ALen-1;
  Result:=0;
  for i:=AStart to AEnd do
    inc(Result,CharToHash[ASource[i]]);
  if Result>FMaxHashIndex then Result:=-1;
end;

function TKeyWordFunctionList.KeyWordToHashIndex(Identifier: PChar): integer;
var i: integer;
begin
  Result:=0;
  i:=20;
  while (i>0) and IsIdentChar[Identifier[0]] do begin
    inc(Result,CharToHash[Identifier[0]]);
    dec(i);
    inc(Identifier);
  end;
  if Result>FMaxHashIndex then Result:=-1;
end;

function TKeyWordFunctionList.KeyWordToHashIndex(Start: PChar; Len: integer
  ): integer;
begin
  Result:=0;
  if Len>20 then Len:=20;
  while (Len>0) do begin
    inc(Result,CharToHash[Start^]);
    dec(Len);
    inc(Start);
  end;
  if Result>FMaxHashIndex then Result:=-1;
end;

function TKeyWordFunctionList.DoIt(const AKeyWord: shortstring): boolean;
var
  i: integer;
  KeyWordFuncItem: PKeyWordFunctionListItem;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(AKeyWord);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      repeat
        KeyWordFuncItem:=@FItems[i];
        if (KeyWordFuncItem^.KeyWord=AKeyWord) then begin
          if Assigned(KeyWordFuncItem^.DoIt) then
            Result:=KeyWordFuncItem^.DoIt()
          else
            Result:=DefaultKeyWordFunction();
          exit;  
        end;
        if KeyWordFuncItem^.IsLast then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

function TKeyWordFunctionList.DoIt(const ASource: string;
  KeyWordStart, KeyWordLen: integer): boolean;
// ! does not test if length(ASource) >= KeyWordStart+KeyWordLen -1
var i, KeyPos, WordPos: integer;
  KeyWordFuncItem: PKeyWordFunctionListItem;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(ASource,KeyWordStart,KeyWordLen);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      dec(KeyWordStart);
      repeat
        KeyWordFuncItem:=@FItems[i];
        if length(KeyWordFuncItem^.KeyWord)=KeyWordLen then begin
          KeyPos:=KeyWordLen;
          WordPos:=KeyWordStart+KeyWordLen;
          while (KeyPos>=1) 
          and (KeyWordFuncItem^.KeyWord[KeyPos]=UpChars[ASource[WordPos]]) do
          begin
            dec(KeyPos);
            dec(WordPos);
          end;
          if KeyPos<1 then begin
            if Assigned(KeyWordFuncItem^.DoIt) then
              Result:=KeyWordFuncItem^.DoIt()
            else
              Result:=DefaultKeyWordFunction();
            exit;
          end;
        end;
        if (KeyWordFuncItem^.IsLast) then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

function TKeyWordFunctionList.DoIt(Identifier: PChar): boolean;
// checks
var i, KeyPos, KeyWordLen: integer;
  KeyWordFuncItem: PKeyWordFunctionListItem;
  IdentifierEnd, WordPos: PChar;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(Identifier);
  IdentifierEnd:=Identifier;
  while IsIdentChar[IdentifierEnd[0]] do inc(IdentifierEnd);
  KeyWordLen:=(PtrInt(IdentifierEnd)-PtrInt(Identifier));
  dec(IdentifierEnd);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      repeat
        KeyWordFuncItem:=@FItems[i];
        if length(KeyWordFuncItem^.KeyWord)=KeyWordLen then begin
          KeyPos:=KeyWordLen;
          WordPos:=IdentifierEnd;
          while (KeyPos>=1)
          and (KeyWordFuncItem^.KeyWord[KeyPos]=UpChars[WordPos[0]]) do
          begin
            dec(KeyPos);
            dec(WordPos);
          end;
          if KeyPos<1 then begin
            if Assigned(KeyWordFuncItem^.DoIt) then
              Result:=KeyWordFuncItem^.DoIt()
            else
              Result:=DefaultKeyWordFunction();
            exit;
          end;
        end;
        if (KeyWordFuncItem^.IsLast) then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

function TKeyWordFunctionList.DoItUppercase(const AnUpperSource: string;
// use this function if ASource upcased
  KeyWordStart, KeyWordLen: integer): boolean;
// ! does not test if length(AnUpperSource) >= KeyWordStart+KeyWordLen -1
var i, KeyPos, WordPos: integer;
  KeyWordFuncItem: PKeyWordFunctionListItem;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(AnUpperSource,KeyWordStart,KeyWordLen);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      dec(KeyWordStart);
      repeat
        KeyWordFuncItem:=@FItems[i];
        if length(KeyWordFuncItem^.KeyWord)=KeyWordLen then begin
          KeyPos:=KeyWordLen;
          WordPos:=KeyWordStart+KeyWordLen;
          while (KeyPos>=1) 
          and (KeyWordFuncItem^.KeyWord[KeyPos]=AnUpperSource[WordPos]) do
          begin
            dec(KeyPos);
            dec(WordPos);
          end;
          if KeyPos<1 then begin
            if Assigned(KeyWordFuncItem^.DoIt) then
              Result:=KeyWordFuncItem^.DoIt()
            else
              Result:=DefaultKeyWordFunction();
            exit;
          end;
        end;
        if (KeyWordFuncItem^.IsLast) then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

procedure TKeyWordFunctionList.Add(const AKeyWord: shortstring;
  const AFunction: TKeyWordFunction);
begin
  AddExtended(AKeyWord,AFunction,nil);
end;

procedure TKeyWordFunctionList.AddExtended(const AKeyWord: shortstring;
  const AFunction: TKeyWordFunction; const ADataFunction: TKeyWordDataFunction
    );
begin
  FSorted:=false;
  if FCount=FCapacity then begin
    FCapacity:=FCapacity*2+10;
    ReAllocMem(FItems,SizeOf(TKeyWordFunctionListItem)*FCapacity);
  end;
  FillChar(FItems[FCount],SizeOF(TKeyWordFunctionListItem),0);
  with FItems[FCount] do begin
    KeyWord:=AKeyWord;
    DoIt:=AFunction;
    DoDataFunction:=ADataFunction;
  end;
  inc(FCount);
end;

procedure TKeyWordFunctionList.Add(List: TKeyWordFunctionList);
var
  i: Integer;
begin
  for i:=0 to List.FCount-1 do begin
    if IndexOf(List.FItems[i].KeyWord)<0 then begin
      AddExtended(List.FItems[i].KeyWord,List.FItems[i].DoIt,
                  List.FItems[i].DoDataFunction);
    end;
  end;
end;

procedure TKeyWordFunctionList.Sort;
// bucketsort
var i, h, NewMaxHashIndex: integer;
  UnsortedItems: PKeyWordFunctionListItem;
  Size: Integer;
begin
  if FSorted then exit;
  if FBucketStart<>nil then begin
    FreeMem(FBucketStart);
    FBucketStart:=nil;
  end;
  // find maximum hash index
  FMaxHashIndex:=99999;
  NewMaxHashIndex:=0;
  for i:=0 to FCount-1 do begin
    h:=KeyWordToHashIndex(FItems[i].KeyWord);
    if h>NewMaxHashIndex then NewMaxHashIndex:=h;
  end;
  FMaxHashIndex:=NewMaxHashIndex;
  // create hash index
  GetMem(FBucketStart,(FMaxHashIndex+1) * SizeOf(integer));
  // compute every hash value count
  for i:=0 to FMaxHashIndex do FBucketStart[i]:=0;
  for i:=0 to FCount-1 do begin
    h:=KeyWordToHashIndex(FItems[i].KeyWord);
    if h>=0 then inc(FBucketStart[h]);
  end;
  // change hash-count-index to bucket-end-index
  h:=0;
  for i:=0 to FMaxHashIndex-1 do begin
    inc(h,FBucketStart[i]);
    if FBucketStart[i]=0 then
      FBucketStart[i]:=-1
    else
      FBucketStart[i]:=h;
  end;
  inc(FBucketStart[FMaxHashIndex],h);
  // copy all items (just the data, not the string contents)
  Size:=sizeof(TKeyWordFunctionListItem)*FCount;
  GetMem(UnsortedItems,Size);
  Move(FItems^,UnsortedItems^,Size);
  // copy unsorted items to Items back and do the bucket sort
  for i:=FCount-1 downto 0 do begin
    h:=KeyWordToHashIndex(UnsortedItems[i].KeyWord);
    if h>=0 then begin
      dec(FBucketStart[h]);
      // copy item back (just the data, not the string contents)
      Move(UnsortedItems[i],FItems[FBucketStart[h]],
           SizeOf(TKeyWordFunctionListItem));
    end;
  end;
  // free UnsortedItems
  FreeMem(UnsortedItems);
  // set IsLast
  if FCount>0 then begin
    for i:=1 to FMaxHashIndex do
      if FBucketStart[i]>0 then
        FItems[FBucketStart[i]-1].IsLast:=true;
    FItems[FCount-1].IsLast:=true;
  end;
  // tidy up
  FSorted:=true;
end;

procedure TKeyWordFunctionList.WriteDebugListing;
var i: integer;
begin
  Sort;
  DebugLn('[TKeyWordFunctionList.WriteDebugListing]');
  DebugLn('  ItemsCount=',dbgs(FCount),'  MaxHash=',dbgs(FMaxHashIndex)
     ,'  Sorted=',dbgs(FSorted));
  for i:=0 to FCount-1 do begin
    DbgOut('    '+dbgs(i)+':');
    with FItems[i] do begin
      DbgOut(' "'+KeyWord+'"');
      DbgOut(' Hash=',dbgs(KeyWordToHashIndex(KeyWord)));
      DbgOut(' IsLast=',dbgs(IsLast));
      DbgOut(' DoIt=',dbgs(Assigned(DoIt)));
    end;
    DebugLn('');
  end;
  DbgOut('  BucketStart array:');
  for i:=0 to FMaxHashIndex do begin
    if FBucketStart[i]>=0 then
    DbgOut(' '+dbgs(i)+'->'+dbgs(FBucketStart[i]));
  end;
  DebugLn('');
end;

function TKeyWordFunctionList.AllwaysTrue: boolean;
begin
  Result:=true;
end;

function TKeyWordFunctionList.AllwaysFalse: boolean;
begin
  Result:=false;
end;

function TKeyWordFunctionList.Count: integer;
begin
  Result:=FCount;
end;

function TKeyWordFunctionList.GetItem(Index: integer
  ): TKeyWordFunctionListItem;
begin
  Result:=FItems[Index];
end;

function TKeyWordFunctionList.IndexOf(const AKeyWord: shortstring): integer;
begin
  Result:=FCount-1;
  while (Result>=0) and (CompareText(FItems[Result].KeyWord,AKeyWord)<>0) do
    dec(Result);
end;

function TKeyWordFunctionList.DoItCaseInsensitive(const AKeyWord: shortstring
  ): boolean;
var i: integer;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(AKeyWord);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      repeat
        if AnsiCompareText(FItems[i].KeyWord,AKeyWord)=0
        then begin
          if Assigned(FItems[i].DoIt) then
            Result:=FItems[i].DoIt()
          else
            Result:=DefaultKeyWordFunction();
          exit;
        end;
        if FItems[i].IsLast then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

function TKeyWordFunctionList.DoDataFunction(Start: PChar; Len: integer;
  Data: pointer): boolean;
var i, KeyPos: integer;
  KeyWordFuncItem: PKeyWordFunctionListItem;
  WordPos: PChar;
  KeyWordEnd: PChar;
begin
  if not FSorted then Sort;
  i:=KeyWordToHashIndex(Start,Len);
  if i>=0 then begin
    i:=FBucketStart[i];
    if i>=0 then begin
      KeyWordEnd:=PChar(Pointer(Start)+Len-1);
      repeat
        KeyWordFuncItem:=@FItems[i];
        if length(KeyWordFuncItem^.KeyWord)=Len then begin
          KeyPos:=Len;
          WordPos:=KeyWordEnd;
          while (KeyPos>=1)
          and (KeyWordFuncItem^.KeyWord[KeyPos]=UpChars[WordPos^]) do
          begin
            dec(KeyPos);
            dec(WordPos);
          end;
          if KeyPos<1 then begin
            if Assigned(KeyWordFuncItem^.DoDataFunction) then
              Result:=KeyWordFuncItem^.DoDataFunction(Data)
            else
              Result:=DefaultKeyWordFunction();
            exit;
          end;
        end;
        if (KeyWordFuncItem^.IsLast) then break;
        inc(i);
      until false;
    end;
  end;
  Result:=DefaultKeyWordFunction();
end;

//-----------------------------------------------------------------------------

var KeyWordLists: TFPList;

procedure InternalInit;
var
  c: char;
  w: word;
begin
  for c:=Low(UpChars) to High(UpChars) do begin
    case c of
    'a'..'z':CharToHash[c]:=ord(c)-ord('a')+1;
    'A'..'Z':CharToHash[c]:=ord(c)-ord('A')+1;
    else CharToHash[c]:=0;
    end;
    UpChars[c]:=upcase(c);
    IsIdentChar[c]:=(c in ['a'..'z','A'..'Z','0'..'9','_']);
  end;
  for w:=Low(word) to High(word) do
    UpWords[w]:=ord(UpChars[chr(w and $ff)])+(ord(UpChars[chr(w shr 8)]) shl 8);

  KeyWordLists:=TFPList.Create;
  
  IsKeyWordMethodSpecifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordMethodSpecifier);
  with IsKeyWordMethodSpecifier do begin
    Add('ABSTRACT'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CDECL'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTDECL'     ,{$ifdef FPC}@{$endif}AllwaysTrue); // used often for macros
    ADD('MWPASCAL'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOSTACKFRAME',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DEPRECATED'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DISPID'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DYNAMIC'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INLINE'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MESSAGE'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OVERLOAD'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OVERRIDE'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PLATFORM'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('POPSTACK'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REGISTER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REINTRODUCE' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('STDCALL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VIRTUAL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsKeyWordProcedureSpecifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordProcedureSpecifier);
  with IsKeyWordProcedureSpecifier do begin
    Add('ASSEMBLER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CDECL'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTDECL'      ,{$ifdef FPC}@{$endif}AllwaysTrue); // used often for macros
    ADD('MWPASCAL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('COMPILERPROC' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DEPRECATED'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXPORT'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTERNAL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PUBLIC'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FAR'          ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FORWARD'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INLINE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IOCHECK'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LOCAL'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NEAR'         ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOSTACKFRAME' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OLDFPCCALL'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OVERLOAD'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PASCAL'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PLATFORM'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('POPSTACK'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REGISTER'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SAVEREGISTERS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('STDCALL'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VARARGS'      ,{$ifdef FPC}@{$endif}AllwaysTrue); // kylix
    Add('['            ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsKeyWordProcedureTypeSpecifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordProcedureTypeSpecifier);
  with IsKeyWordProcedureTypeSpecifier do begin
    Add('STDCALL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REGISTER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('POPSTACK'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CDECL'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTDECL'     ,{$ifdef FPC}@{$endif}AllwaysTrue); // used often for macros
    ADD('MWPASCAL'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PASCAL'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FAR'         ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NEAR'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOSTACKFRAME',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DEPRECATED'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PLATFORM'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsKeyWordProcedureBracketSpecifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordProcedureBracketSpecifier);
  with IsKeyWordProcedureBracketSpecifier do begin
    Add('ALIAS'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PUBLIC'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTERNAL'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERNPROC'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERNCONST'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SAVEREGISTERS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IOCHECK'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsKeyWordSection:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordSection);
  with IsKeyWordSection do begin
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PACKAGE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsKeyWordInConstAllowed:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsKeyWordInConstAllowed);
  with IsKeyWordInConstAllowed do begin
    Add('NOT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LOW',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('HIGH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AS',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsKeyWord:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsKeyWord);
  with WordIsKeyWord do begin
    Add('AS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ARRAY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONST',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONSTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DESTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DOWNTO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ELSE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('END',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCEPT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXPORTS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALLY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FUNCTION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('GOTO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IF',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INHERITED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INLINE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LABEL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OF',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OPERATOR',{$ifdef FPC}@{$endif}AllwaysTrue); // not for Delphi
    //Add('ON',{$ifdef FPC}@{$endif}AllwaysTrue); // not for Delphi
    //Add('OUT',{$ifdef FPC}@{$endif}AllwaysTrue); // not in MacPas mode
    Add('OR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PACKED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROCEDURE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROPERTY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RAISE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RESOURCESTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SET',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THEN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TYPE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNTIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('USES',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THREADVAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WHILE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WITH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsDelphiKeyWord:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsDelphiKeyWord);
  with WordIsDelphiKeyWord do begin
    Add('AS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ARRAY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONST',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONSTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DESTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DOWNTO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ELSE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('END',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCEPT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXPORTS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALLY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FUNCTION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('GOTO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IF',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INHERITED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INLINE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LABEL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OF',{$ifdef FPC}@{$endif}AllwaysTrue);
    //Add('OPERATOR',{$ifdef FPC}@{$endif}AllwaysTrue); // not for Delphi
    //Add('ON',{$ifdef FPC}@{$endif}AllwaysTrue); // not for Delphi
    Add('OR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PACKED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROCEDURE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROPERTY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RAISE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RESOURCESTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SET',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THEN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TYPE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNTIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('USES',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THREADVAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WHILE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WITH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  IsWordBuiltInFunc:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(IsWordBuiltInFunc);
  with IsWordBuiltInFunc do begin
    Add('LOW',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('HIGH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LO',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('HI',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PREC',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SUCC',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LENGTH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SETLENGTH',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INC',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DEC',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('COPY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SIZEOF',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WRITE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WRITELN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('READ',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('READLN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TYPEOF',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASSIGNED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INCLUDE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCLUDE',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsTermOperator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsTermOperator);
  with WordIsTermOperator do begin
    Add('+',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('-',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('*',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NOT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsPropertySpecifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsPropertySpecifier);
  with WordIsPropertySpecifier do begin
    Add('INDEX',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('READ',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WRITE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('STORED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DEFAULT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NODEFAULT',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsBlockKeyWord:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBlockKeyWord);
  with WordIsBlockKeyWord do begin
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DISPINTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('END',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCEPT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALLY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNTIL',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  EndKeyWordFuncList:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(EndKeyWordFuncList);
  with EndKeyWordFuncList do begin
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  PackedTypesKeyWordFuncList:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(PackedTypesKeyWordFuncList);
  with PackedTypesKeyWordFuncList do begin
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DISPINTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ARRAY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SET',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  GenericTypesKeyWordFuncList:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(GenericTypesKeyWordFuncList);
  with GenericTypesKeyWordFuncList do begin
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DISPINTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  BlockStatementStartKeyWordFuncList:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(BlockStatementStartKeyWordFuncList);
  with BlockStatementStartKeyWordFuncList do begin
    Add('BEGIN' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  UnexpectedKeyWordInBeginBlock:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(UnexpectedKeyWordInBeginBlock);
  with UnexpectedKeyWordInBeginBlock do begin
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONST',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONSTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DESTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FUNCTION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROCEDURE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RESOURCESTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SET',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THREADVAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TYPE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VAR',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  UnexpectedKeyWordInAsmBlock:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(UnexpectedKeyWordInAsmBlock);
  with UnexpectedKeyWordInAsmBlock do begin
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONST',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONSTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DESTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FUNCTION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROCEDURE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RESOURCESTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SET',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('THREADVAR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('VAR',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsLogicalBlockStart:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLogicalBlockStart);
  with WordIsLogicalBlockStart do begin
    Add('(',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('[',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('{',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CLASS',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONSTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DESTRUCTOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DISPINTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FUNCTION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTERFACE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LIBRARY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OBJECT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PACKAGE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PRIVATE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROCEDURE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROGRAM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PROTECTED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PUBLIC',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PUBLISHED',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('RECORD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsLogicalBlockEnd:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLogicalBlockEnd);
  with WordIsLogicalBlockEnd do begin
    Add(')',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add(']',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('}',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('END',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNTIL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IMPLEMENTATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INITIALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FINALIZATION',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsLogicalBlockMiddle:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLogicalBlockMiddle);
  with WordIsLogicalBlockMiddle do begin
    Add('FINALLY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCEPT',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsBlockStatementStart:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBlockStatementStart);
  with WordIsBlockStatementStart do begin
    Add('(',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('[',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('{',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ASM',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BEGIN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CASE',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REPEAT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNIT',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsBlockStatementEnd:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBlockStatementEnd);
  with WordIsBlockStatementEnd do begin
    Add(')',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add(']',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('}',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('END',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('UNTIL',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsBlockStatementMiddle:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBlockStatementMiddle);
  with WordIsBlockStatementMiddle do begin
    Add('FINALLY',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXCEPT',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;

  WordIsBinaryOperator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBinaryOperator);
  with WordIsBinaryOperator do begin
    Add('+'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('-'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('*'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('/'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OR' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('='  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<>' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>=' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<=' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IS' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AS' ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsLvl1Operator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLvl1Operator);
  with WordIsLvl1Operator do begin
    Add('NOT',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('@'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsLvl2Operator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLvl2Operator);
  with WordIsLvl2Operator do begin
    Add('*'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('/'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AS' ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsLvl3Operator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLvl3Operator);
  with WordIsLvl3Operator do begin
    Add('+'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('-'  ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('OR' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsLvl4Operator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsLvl4Operator);
  with WordIsLvl4Operator do begin
    Add('=' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<>',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>=',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<=',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IS',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsBooleanOperator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsBooleanOperator);
  with WordIsBooleanOperator do begin
    Add('=' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<>',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('>=',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('<=',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IN',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('IS',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsOrdNumberOperator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsOrdNumberOperator);
  with WordIsOrdNumberOperator do begin
    Add('OR' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('XOR' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('AND',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHL',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHR',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DIV',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('MOD',{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsNumberOperator:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsNumberOperator);
  with WordIsNumberOperator do begin
    Add('+' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('-' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('*' ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  
  WordIsPredefinedFPCIdentifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsPredefinedFPCIdentifier);
  with WordIsPredefinedFPCIdentifier do begin
    Add('ANSISTRING' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BOOLEAN'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BYTEBOOL'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CARDINAL'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CHAR'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('COMP'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CURRENCY'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DOUBLE'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTENDED'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FALSE'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FILE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INT64'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LONGBOOL'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NIL'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('POINTER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('QWORD'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REAL'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHORTSTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SINGLE'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('STRING'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TEXT'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRUE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WIDECHAR'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WIDESTRING' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXIT'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BREAK'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONTINUE'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    // only fpc 1.1
    Add('LONGWORD'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WORD'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LONGINT'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SMALLINT'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHORTINT'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BYTE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
  WordIsPredefinedFPCIdentifier.Add(IsWordBuiltInFunc);
  
  WordIsPredefinedDelphiIdentifier:=TKeyWordFunctionList.Create;
  KeyWordLists.Add(WordIsPredefinedDelphiIdentifier);
  with WordIsPredefinedDelphiIdentifier do begin
    Add('ANSISTRING' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BOOLEAN'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CARDINAL'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CHAR'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('COMP'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CURRENCY'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('DOUBLE'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXTENDED'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FALSE'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('FILE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('HIGH'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INT64'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('INTEGER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LENGTH'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LONGWORD'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('LOW'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('NIL'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('ORD'        ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('POINTER'    ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PREC'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('QWORD'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('REAL'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SHORTSTRING',{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SINGLE'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SIZEOF'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('STRING'     ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('SUCC'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TEXT'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('TRUE'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WIDECHAR'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WIDESTRING' ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('WORD'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('EXIT'       ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('BREAK'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('CONTINUE'   ,{$ifdef FPC}@{$endif}AllwaysTrue);
    Add('PCHAR'      ,{$ifdef FPC}@{$endif}AllwaysTrue);
  end;
end;

procedure InternalFinal;
var i: integer;
begin
  for i:=0 to KeyWordLists.Count-1 do
    TKeyWordFunctionList(KeyWordLists[i]).Free;
  KeyWordLists.Free;
  KeyWordLists:=nil;
end;


initialization
  InternalInit;
  
finalization
  InternalFinal;
  
end.

