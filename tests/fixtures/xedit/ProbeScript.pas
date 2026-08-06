unit ProbeScript;

function Initialize: Integer;
begin
  AddMessage('SEG probe script initialized');
end;

function Finalize: Integer;
var
  lines: TStringList;
begin
  lines := TStringList.Create;
  lines.Add('probe=passed');
  lines.Add('file-count=' + IntToStr(FileCount));
  lines.SaveToFile(ScriptsPath + 'xedit-probe.txt');
  lines.Free;
  AddMessage('SEG probe script finalized');
end;

end.
