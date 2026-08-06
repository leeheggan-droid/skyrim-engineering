unit InspectOriginalFixture;

var
  lines: TStringList;

procedure Walk(e: IInterface; depth: Integer);
var
  i: Integer;
  child: IInterface;
begin
  if depth > 8 then
    Exit;
  if Signature(e) <> '' then
    lines.Add(StringOfChar(' ', depth * 2) + Signature(e) + '|' + EditorID(e));
  for i := 0 to Pred(ElementCount(e)) do begin
    child := ElementByIndex(e, i);
    if Assigned(child) then
      Walk(child, depth + 1);
  end;
end;

function Initialize: Integer;
var
  i: Integer;
  f: IInterface;
begin
  lines := TStringList.Create;
  for i := 0 to Pred(FileCount) do
    if SameText(GetFileName(FileByIndex(i)), 'SEG_CK_Practical3.esp') then
      f := FileByIndex(i);
  if not Assigned(f) then
    raise Exception.Create('SEG_CK_Practical3.esp is not loaded');
  lines.Add('fixture=' + GetFileName(f));
  lines.Add('master-count=' + IntToStr(MasterCount(f)));
  lines.Add('record-count=' + IntToStr(RecordCount(f)));
  Walk(f, 0);
  lines.SaveToFile(ProgramPath + 'SEG-ck-practical3-inspection.txt');
end;

function Finalize: Integer;
begin
  lines.Free;
end;

end.
