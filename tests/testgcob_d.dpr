program testgcob_d;

{$APPTYPE CONSOLE}

uses
  TextTestRunner,
  TestFramework,
  tcgcobj,
  SysUtils,
  gcobj in '..\src\gcobj.pas';

begin
  TextTestRunner.RunRegisteredTests();
end.
