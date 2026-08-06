{
  Read-only xEdit inspection fixture for the Skyrim engineering expertise gate.
  It writes a bounded report and intentionally performs no edit or save call.
}
unit InspectReadOnly;

function Initialize: Integer;
var
  i, j, k, modifiedCount, nonEmptyContainerCount: Integer;
  f, header, masters, groupNode, recordNode, masterNode, winningNode,
    questGroup, vmad: IInterface;
  lines, containers: TStringList;
  outputPath: String;
begin
  modifiedCount := 0;
  lines := TStringList.Create;
  containers := TStringList.Create;
  try
    lines.Add('inspection-mode=read-only');
    lines.Add('xedit-version-number=' + IntToStr(wbVersionNumber));
    lines.Add('game=' + wbGameName);
    lines.Add('loaded-file-count=' + IntToStr(FileCount));

    for i := 0 to Pred(FileCount) do begin
      f := FileByIndex(i);
      if not Assigned(f) then
        Continue;
      if GetElementState(f, esModified) then
        Inc(modifiedCount);
      if not SameText(GetFileName(f), 'Skyrim.esm') and
         not SameText(GetFileName(f), 'Update.esm') then
        Continue;

      lines.Add('file=' + GetFileName(f));
      header := ElementByIndex(f, 0);
      lines.Add('header-signature=' + Signature(header));
      lines.Add('header-flags=' + GetElementEditValues(header, 'Record Header\Record Flags'));
      lines.Add('header-version=' + GetElementEditValues(header, 'HEDR\Version'));
      lines.Add('header-record-count=' + GetElementEditValues(header, 'HEDR\Number of Records'));
      masters := ElementByName(header, 'Master Files');
      if Assigned(masters) then
        for j := 0 to Pred(ElementCount(masters)) do
          lines.Add('master=' + GetElementEditValues(ElementByIndex(masters, j), 'MAST'));

      if SameText(GetFileName(f), 'Update.esm') then begin
        { Locate a bounded first override sample from a top-level group. }
        for j := 1 to Pred(ElementCount(f)) do begin
          groupNode := ElementByIndex(f, j);
          for k := 0 to Pred(ElementCount(groupNode)) do begin
            recordNode := ElementByIndex(groupNode, k);
            if Assigned(recordNode) and not IsMaster(recordNode) then begin
              masterNode := MasterOrSelf(recordNode);
              winningNode := WinningOverride(recordNode);
              lines.Add('override-sample=' + Signature(recordNode) + ':' +
                IntToHex(FormID(recordNode), 8));
              lines.Add('override-master-file=' + GetFileName(GetFile(masterNode)));
              lines.Add('override-winning-file=' + GetFileName(GetFile(winningNode)));
              Break;
            end;
          end;
          if Assigned(recordNode) and not IsMaster(recordNode) then
            Break;
        end;

        { Bound VMAD inspection to quests in Update.esm. }
        questGroup := GroupBySignature(f, 'QUST');
        if Assigned(questGroup) then
          for j := 0 to Pred(ElementCount(questGroup)) do begin
            recordNode := ElementByIndex(questGroup, j);
            vmad := ElementBySignature(recordNode, 'VMAD');
            if Assigned(vmad) then begin
              lines.Add('vmad-sample=' + EditorID(recordNode));
              lines.Add('vmad-script-count=' +
                IntToStr(ElementCount(ElementByPath(vmad, 'Scripts'))));
              Break;
            end;
          end;
      end;
    end;

    ResourceContainerList(containers);
    nonEmptyContainerCount := 0;
    for i := 0 to Pred(containers.Count) do
      if Trim(ExtractFileName(containers[i])) <> '' then
        Inc(nonEmptyContainerCount);
    lines.Add('resource-container-count=' + IntToStr(nonEmptyContainerCount));
    lines.Add('resource-container-list-retained=no');
    { esModified reflects xEdit's in-memory load/normalization state. It does
      not prove a disk write; the external harness owns before/after hashes. }
    lines.Add('in-memory-normalized-file-count=' + IntToStr(modifiedCount));

    outputPath := ScriptsPath + 'xedit-read-only-inspection.txt';
    lines.SaveToFile(outputPath);
    AddMessage('SEG inspection saved: ' + outputPath);
  finally
    containers.Free;
    lines.Free;
  end;
end;

end.
