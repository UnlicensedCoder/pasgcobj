unit tcgcobj;
{$ifdef FPC}
{$mode objfpc}{$H+}
{$endif}

interface

uses
  Classes, SysUtils, Variants,
  {$ifdef FPC}
  fpcunit, testregistry,
  {$ELSE}
  TestFramework,
  {$ENDIF}
  gcobj;

type

  { TTestGCObj }

  TTestGCObj= class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGC1;
    procedure TestGC2;
  end;

implementation

type
  INode = interface
  ['{67228E58-36F6-41A5-A8F9-80AA8DA78D75}']
    procedure SetMe(const Node: INode);
    function GetMe: INode;
    function GetItem(Index: Integer): INode;
    function GetCount: Integer;
    procedure Add(const Node: INode);
    procedure SetStatic(Index: Integer; Node: INode);

    property Me: INode read GetMe write SetMe;
    property Items[Index: Integer]: INode read GetItem;
    property Count: Integer read GetCount;
  end;

  TObj = object
  public
    FVar: INode;
  end;

  TNodeObj = class(TGCObject, INode)
  private
    FItems: array of INode;
    FCount: Integer;
    FMe: INode;
    FStatic: array[0..2] of INode;
    FStaticVar: array[0..2] of Variant;
    FStaticObj: array[0..2] of TObj;
    FVar: Variant;
    FObj: TObj;

    procedure SetMe(const Node: INode);
    function GetMe: INode;
    function GetItem(Index: Integer): INode;
    function GetCount: Integer;
    procedure Add(const Node: INode);
    procedure SetStatic(Index: Integer; Node: INode);
  end;

function NewNode: INode;
begin
  Result := TNodeObj.Create;
end;

{ TNodeObj }

procedure TNodeObj.Add(const Node: INode);
begin
  if FCount = Length(FItems) then
    SetLength(FItems, FCount + 4);
  FItems[FCount] := Node;
  Inc(FCount);
end;

function TNodeObj.GetItem(Index: Integer): INode;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.CreateFmt('Index %d out of bound', [Index]);
  Result := FItems[Index];
end;

function TNodeObj.GetCount: Integer;
begin
  Result := fCount;
end;

function TNodeObj.GetMe: INode;
begin
  Result := FMe;
end;

procedure TNodeObj.SetMe(const Node: INode);
begin
  FMe := Node;
  FVar := Node;
  FObj.FVar := Node;
end;

procedure TNodeObj.SetStatic(Index: Integer; Node: INode);
begin
  if (Index < Low(FStatic)) or (Index > High(FStatic)) then Exit;

  FStatic[Index] := Node;
  FStaticVar[Index] := Node;
  FStaticObj[Index].FVar := Node;
end;

{ TTestGCObj }

procedure TTestGCObj.TestGC1;

  procedure test1;
  var
    node,sub: INode;
  begin
    node := NewNode;
    sub := newNode;
    node.Add(NewNode);
    node.Me := node;
    sub.Add(node);
    node.Add(sub);
    sub.SetStatic(0, NewNode);
    sub.SetStatic(1, sub);
    sub.Me := sub;
    node.SetStatic(0, node.Me);
    node.SetStatic(1, sub.Me);
  end;
var
  objCnt, objSizes: Integer;
begin
  test1;
  Collect;
  GetTotals(objCnt, objSizes);
  CheckEquals(0, objCnt + objSizes, 'After Collect, objCnt=1');
end;

procedure TTestGCObj.TestGC2;

  procedure test2(var node: INode);
  var
    sub: INode;
  begin
    node := NewNode;
    node.Me := node;

    sub := newNode;
    sub.Add(node);
    sub.SetStatic(0, NewNode);
    sub.SetStatic(1, sub);
    sub.Me := sub;
  end;

var
  objCnt, objSizes: Integer;
  intf: INode;
begin
  test2(intf);
  Collect;
  GetTotals(objCnt, objSizes);
  CheckEquals(1, objCnt, 'Before intf:=nil');

  intf := nil;
  Collect;
  GetTotals(objCnt, objSizes);
  CheckEquals(0, objCnt, 'After intf:=nil');

end;

procedure TTestGCObj.SetUp;
begin
  inherited;
end;

procedure TTestGCObj.TearDown;
begin
  inherited;
end;

initialization
{$ifdef FPC}
  RegisterTest(TTestGCObj);
{$ELSE}
  RegisterTest(TTestGCObj.Suite);
{$ENDIF}
end.

