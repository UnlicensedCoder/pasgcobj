{ Some RTTI record type are copied from rtti.inc }

{$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
  {$define USE_PACKED}
{$endif}
{$ifdef VER2_6}
  {$define USE_PACKED}
{$endif}

type
  PRecordElement=^TRecordElement;
  TRecordElement=
{$ifdef USE_PACKED}
  packed
{$endif USE_PACKED}
  record
    TypeInfo: Pointer;
    {$ifdef VER2_6}
    Offset: Longint;
    {$else}
    Offset: SizeInt;
    {$endif}
  end;

  PRecordInfo=^TRecordInfo;
  TRecordInfo=
{$ifdef USE_PACKED}
  packed
{$endif USE_PACKED}
  record
    Size: Longint;
    Count: Longint;
    { Elements: array[count] of TRecordElement }
  end;

  PArrayInfo=^TArrayInfo;
  TArrayInfo=
{$ifdef USE_PACKED}
  packed
{$endif USE_PACKED}
  record
    Size: SizeInt;
    ElCount: SizeInt;
    ElInfo: Pointer;
    DimCount: Byte;
    Dims:array[0..255] of Pointer;
  end;

  pdynarraytypedata = ^tdynarraytypedata;
  tdynarraytypedata =
{$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
  packed
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
  record
    elSize : SizeUInt;
    elType : Pointer;
    varType : Longint;
  end;

function aligntoptr(p : pointer) : pointer;inline;
begin
{$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
  result:=align(p,sizeof(p));
{$else FPC_REQUIRES_PROPER_ALIGNMENT}
  result:=p;
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
end;

function RTTIArraySize(typeInfo: Pointer): SizeInt;
begin
  typeInfo:=aligntoptr(typeInfo+2+PByte(typeInfo)[1]);
  {$ifdef VER2_6}
  result:=PArrayInfo(typeInfo)^.Size*PArrayInfo(typeInfo)^.ElCount;
  {$else}
  result:=PArrayInfo(typeInfo)^.Size;
  {$endif}
end;

function RTTIRecordSize(typeInfo: Pointer): SizeInt;
begin
  typeInfo:=aligntoptr(typeInfo+2+PByte(typeInfo)[1]);
  result:=PRecordInfo(typeInfo)^.Size;
end;

function RTTISize(typeInfo: Pointer): SizeInt;
begin
  case TTypeKind(typeinfo^) of
    tkAString,tkWString,tkUString,
    tkInterface,tkDynarray:
      result:=sizeof(Pointer);
{$ifdef FPC_HAS_FEATURE_VARIANTS}
    tkVariant:
      result:=sizeof(TVarData);
{$endif FPC_HAS_FEATURE_VARIANTS}
    tkArray:
      result:=RTTIArraySize(typeinfo);
    tkObject,tkRecord:
      result:=RTTIRecordSize(typeinfo);
  else
    result:=-1;
  end;
end;

procedure VisitRecord(Data, TypeInfo: Pointer; cb: TVisitProc); forward;
procedure VisitArray(P, typeInfo: Pointer; cb: TVisitProc); forward;
procedure VisitDynArray(P, typeInfo: Pointer; cb: TVisitProc); forward;
procedure VisitFields(P, typeInfo: Pointer; elemCount: Cardinal; cb: TVisitProc); forward;

procedure VisitField(P, typeInfo: Pointer; cb: TVisitProc);
var
  gcIntf: IGCSupport;
begin
  case TTypeKind(typeInfo^) of
    tkVariant:
      if TVarData(P^).VType in [varUnknown, varDispatch] then
      begin
        if Assigned(TVarData(P^).VUnknown)
            and (IUnknown(TVarData(P^).VUnknown)
                .QueryInterface(IGCSupport, gcIntf) = S_OK) then
        begin
          cb(@TVarData(P^).VUnknown, gcIntf, nil);
          gcIntf := nil;
        end;
      end;
    tkArray:
      VisitArray(P, typeInfo, cb);
    tkDynArray:
      VisitDynArray(P, typeInfo, cb);
    tkRecord, tkObject:
      VisitRecord(P, typeInfo, cb);
    tkInterface:
      if Assigned(Pointer(P^))
        and (IInterface(P^).QueryInterface(IGCSupport, gcIntf) = S_OK) then
      begin
        cb(P, gcIntf, nil);
        gcIntf := nil;
      end;
  end;
end;

procedure VisitDynArray(P, typeInfo: Pointer; cb: TVisitProc);
type
  TDummyDynArray = array of Byte;
var
  TD: PDynArrayTypeData;
begin
  if Pointer(P^) = nil then Exit;
  TD := PDynArrayTypeData(aligntoptr(typeInfo + 2 + PByte(typeInfo)[1]));
  if TD^.elType = nil then Exit; // elType = nil if no require cleanup

  VisitFields(Pointer(P^), TD^.elType, Length(TDummyDynArray(P^)), cb);
end;

procedure VisitFields(P, typeInfo: Pointer; elemCount: Cardinal; cb: TVisitProc);
var
  elemSize: SizeInt;
begin
  elemSize := RTTISize(typeInfo);
  while elemCount > 0 do
  begin
    VisitField(P, typeInfo, cb);
    Dec(elemCount);
    Inc(P, elemSize);
  end;
end;

procedure VisitRecord(Data, TypeInfo: Pointer; cb: TVisitProc);
var
  count,
  i : longint;
begin
  typeInfo := aligntoptr(typeInfo+2+PByte(typeInfo)[1]);
  Count := PRecordInfo(typeInfo)^.Count;
  Inc(PRecordInfo(typeInfo));
  { Process elements }
  for i := 1 to count do
  begin
    VisitField(Data + PRecordElement(typeInfo)^.Offset, PRecordElement(typeInfo)^.TypeInfo, cb);
    Inc(PRecordElement(typeInfo));
  end;
end;

{$ifdef VER2_6}
procedure VisitArray(Data, typeInfo: Pointer; cb: TVisitProc);
var
  i: SizeInt;
begin
  typeInfo := aligntoptr(typeInfo+2+PByte(typeInfo)[1]);
  { Process elements }
  for I := 0 to PArrayInfo(typeInfo)^.ElCount-1 do
  begin
    cb(Data, PArrayInfo(typeInfo)^.ElInfo, nil);
    Inc(Data, PArrayInfo(typeInfo)^.Size);
  end;
end;
{$else}
procedure VisitArray(P, typeInfo: Pointer; cb: TVisitProc);
var
  i, Count, ElSize: SizeInt;
  Info: Pointer;
begin
  typeInfo := aligntoptr(typeInfo + 2 + PByte(typeInfo)[1]);
  Count := PArrayInfo(typeInfo)^.ElCount;
  { no elements to process => exit }
  if Count = 0 then Exit;

  ElSize := PArrayInfo(typeInfo)^.Size div Count;
  Info := PArrayInfo(typeInfo)^.ElInfo;
  { Process elements }
  for I := 0 to Count - 1 do
  begin
    VisitField(P, Info, cb);
    Inc(P, ElSize);
  end;
end;

{$endif}


