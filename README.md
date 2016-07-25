# object garbage collect for freepascal/delphi

## 说明

  这个单元主要解决接口循环引用导致不能释放的问题。它通过RTTI遍历vmtInit表所有的接口字段，计算出真实的引用计数，并把计数为0的字段释放（调用IInterface._Release）。
  
## 用法

  1. 从类 TGCObject 继承，和之前一样的方式进行代码设计。
  2. 使用接口之后，调用gcobj单元的Collect。（需要确保所有明确的或隐含的局部变量已经清除之后）
  
## 示例

```
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

procedure Demo1;
  procedure proc1;
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
	// 请注意不要在这里调用Collect，因为 node.Add(NewNode) 此句将生成一个局部变量，在proc1 退出之前不会释放。比较好的方法是在此函数之外调用Collect
  end;

begin
  proc1;
  Collect;
end;

```

