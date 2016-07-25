unit gcobj;
{$ifdef FPC}
{$mode delphi}{$H+}
{$warn 5024 off  param not used}
{$endif}
interface
uses Classes;

type
  PGCData = ^TGCData;
  TGCData = record
    Prev, Next: PGCData;
    RefCnt, GCRefs: Integer;
    This: TInterfacedObject;
  end;

  IGCSupport = interface
  ['{26ABD806-7C56-4B6E-9696-B2E7E674330F}']
    function GetGCData: PGCData;
  end;

  TGCObject = class(TInterfacedObject, IGCSupport)
  private
    FGCData: TGCData;
    function GetGCData: PGCData;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

procedure Collect;
procedure GetTotals(out objCnt, objSizes: Integer);

implementation
uses TypInfo;

threadvar
  Root: TGCData;

type
  TVisitProc = procedure (FieldPtr: Pointer; const Intf: IGCSupport; Data: Pointer);

{$ifdef FPC}
{$I gcrtti.inc}

procedure TraverseObj(obj: TObject; cb: TVisitProc; data: Pointer);
var
  vmt: PVmt;
  temp: pointer;
begin
  vmt := PVmt(obj.ClassType);
  while vmt <> nil do
  begin
    Temp := vmt^.vInitTable;
       { The RTTI format matches one for records, except the type is tkClass.
         Since RecordRTTI does not check the type, calling it yields the desired result. }
    if Assigned(Temp) then
      VisitRecord(obj, temp, cb);
    vmt:= vmt^.vParent;
  end;
end;

{$ELSE}
procedure TraverseObj(obj: TObject; cb: TVisitProc; data: Pointer);
type
  TFieldInfo = packed record
    TypeInfo: PPTypeInfo;
    Offset: Cardinal;
  end;

  PFieldTable = ^TFieldTable;
  TFieldTable = packed record
    X: Word;
    Size: Cardinal;
    Count: Cardinal;
    Fields: array [0..0] of TFieldInfo;
  end;

  PDynArrayTypeInfo = ^TDynArrayTypeInfo;
  TDynArrayTypeInfo = packed record
    X: Word;
    elSize: Longint;
    elType: ^PDynArrayTypeInfo;
    varType: Integer;
  end;

  TDummyDynArray = array of Pointer;

  procedure VisitArray(p: Pointer; typeInfo: Pointer; elemCount: Cardinal); forward;
  procedure VisitRecord(p: Pointer; typeInfo: Pointer); forward;

  procedure VisitDynArray(P: PPointer; typeInfo: Pointer);
  var
    TD: PDynArrayTypeInfo;
  begin
    if P^ = nil then Exit;

    TD := PDynArrayTypeInfo(Integer(typeInfo) + Byte(PTypeInfo(typeInfo).Name[0]));
    if TD^.elType = nil then Exit; // elType = nil if no require cleanup

    VisitArray(P^, TD^.elType^, Length(TDummyDynArray(P^)));
  end;

  procedure VisitArray(p: Pointer; typeInfo: Pointer; elemCount: Cardinal);
  var
    gcIntf: IGCSupport;
    FT: PFieldTable;
  begin
    case PTypeInfo(typeInfo).Kind of
      tkVariant:
        while elemCount > 0 do
        begin
          if TVarData(P^).VType in [varUnknown, varDispatch] then
          begin
            if Assigned(TVarData(P^).VUnknown)
                and (IUnknown(TVarData(P^).VUnknown)
                    .QueryInterface(IGCSupport, gcIntf) = S_OK) then
            begin
              cb(@TVarData(P^).VUnknown, gcIntf, data);
              gcIntf := nil;
            end;
          end;
          Inc(PByte(P), sizeof(Variant));
          Dec(elemCount);
        end;
      tkArray:
        begin
          FT := PFieldTable(Integer(typeInfo) + Byte(PTypeInfo(typeInfo).Name[0]));
          while elemCount > 0 do
          begin
            VisitArray(P, FT.Fields[0].TypeInfo^, FT.Count);
            Inc(PByte(P), FT.Size);
            Dec(elemCount);
          end;
        end;
      tkInterface:
        while elemCount > 0 do
        begin
          if Assigned(Pointer(P^))
            and (IInterface(P^).QueryInterface(IGCSupport, gcIntf) = S_OK) then
          begin
            cb(P, gcIntf, data);
            gcIntf := nil;
          end;
          Inc(PPointer(P), 1);
          Dec(elemCount);
        end;
      tkDynArray:
        while elemCount > 0 do
        begin
          VisitDynArray(P, typeInfo);
          Inc(PPointer(P), 1);
          Dec(elemCount);
        end;
      tkRecord:
        begin
          FT := PFieldTable(Integer(typeInfo) + Byte(PTypeInfo(typeInfo).Name[0]));
          while elemCount > 0 do
          begin
            VisitRecord(P, typeInfo);
            Inc(PByte(P), FT^.Size);
            Dec(elemCount);
          end;
        end;
    end;
  end;

  procedure VisitRecord(p: Pointer; typeInfo: Pointer);
  var
    FT: PFieldTable;
    I: Cardinal;
  begin
    FT := PFieldTable(Integer(typeInfo) + Byte(PTypeInfo(typeInfo).Name[0]));
    for I := 0 to FT.Count-1 do
      VisitArray(PPointer(Cardinal(P) + FT.Fields[I].Offset), FT.Fields[I].TypeInfo^, 1);
  end;
var
  ClassPtr: TClass;
  InitTable: Pointer;
begin
  ClassPtr := Obj.ClassType;
  InitTable := PPointer(Integer(ClassPtr) + vmtInitTable)^;
  while (ClassPtr <> nil) and (InitTable <> nil) do
  begin
    VisitRecord(Obj, InitTable);
    ClassPtr := ClassPtr.ClassParent;
    if ClassPtr <> nil then
      InitTable := PPointer(Integer(ClassPtr) + vmtInitTable)^;
  end;
end;
{$ENDIF}

procedure VisitDecRefs(P: Pointer; const Intf: IGCSupport; data: Pointer);
var
  gc: PGCData;
begin
  gc := intf.GetGCData;

  Assert(gc^.GCRefs > 0, 'Has some errors if gc^.GCRefs < 1');
  if gc^.GCRefs > 0 then Dec(gc^.GCRefs);
end;

procedure VisitCleanup(P: Pointer; const Intf: IGCSupport; data: Pointer);
var
  gc: PGCData;
begin
  gc := intf.GetGCData;
  if gc^.GCRefs = 0 then
    IInterface(P^) := nil;
end;

procedure RemoveFromLink(var gc: TGCData);
begin
  if gc.Next <> nil then
    gc.Next.Prev := gc.Prev;
  gc.Prev.Next := gc.Next;
  gc.Next := nil;
  gc.Prev := nil; 
end;

procedure GetCleanupList(list: TList);
var
  gc: PGCData;
begin
  gc := Root.Next;
  while gc <> nil do
  begin
    if gc^.GCRefs = 0 then
      list.Add(gc);
    gc := gc.Next;
  end;
end;

procedure Collect;
var
  gc: PGCData;
  list: TList;
  i: Integer;
begin
  gc := Root.Next;
  while gc <> nil do
  begin
    gc.RefCnt := gc.This.RefCount;
    gc.GCRefs := gc.RefCnt;
    gc := gc.Next;
  end;

  // 减去循环引用，得到真实被引用的计数
  gc := Root.Next;
  while gc <> nil do
  begin
    TraverseObj(gc^.This, @VisitDecRefs, nil);
    gc := gc.Next;
  end;

  // 遍历所有的对象，将真实引用计数为0的接口释放
  list := TList.Create;
  try
    GetCleanupList(list);
    for i := 0 to list.Count - 1 do
      TraverseObj(PGCData(list[i])^.This, @VisitCleanup, nil);
  finally
    list.Free;
  end;
end;

procedure GetTotals(out objCnt, objSizes: Integer);
var
  gc: PGCData;
begin
  objCnt := 0;
  objSizes := 0;
  gc := Root.Next;
  while gc <> nil do
  begin
    Inc(objCnt);
    Inc(objSizes, gc.This.InstanceSize);
    gc := gc.Next;
  end;
end;

{ TGCObject }

procedure TGCObject.AfterConstruction;
begin
  inherited;
  FGCData.This := Self;
  FGCData.Next := Root.Next;
  FGCData.Prev := @Root;

  if Root.Next <> nil then Root.Next.Prev := @FGCData;
  Root.Next := @FGCData;
end;

procedure TGCObject.BeforeDestruction;
begin
  inherited;
  RemoveFromLink(FGCData);
end;

function TGCObject.GetGCData: PGCData;
begin
  Result := @FGCData;
end;

end.
