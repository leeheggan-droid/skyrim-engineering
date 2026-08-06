{
  Reopens the original fixture and minimal patch, then proves the override
  winner without modifying or saving either file.
}
unit VerifyMinimalPatch;

function Initialize: Integer;
var
  i: Integer;
  sourceFile, patchFile, sourceRecord, patchRecord, winner, miscGroup: IInterface;
begin
  Result := 1;
  for i := 0 to Pred(FileCount) do begin
    if SameText(GetFileName(FileByIndex(i)), 'SEG_CK_Practical3.esp') then
      sourceFile := FileByIndex(i);
    if SameText(GetFileName(FileByIndex(i)), 'SEG_MinimalPatch.esp') then
      patchFile := FileByIndex(i);
  end;
  if not Assigned(sourceFile) then
    raise Exception.Create('SEG_CK_Practical3.esp is not loaded on reopen');
  if not Assigned(patchFile) then
    raise Exception.Create('SEG_MinimalPatch.esp is not loaded on reopen');

  miscGroup := GroupBySignature(sourceFile, 'MISC');
  sourceRecord := MainRecordByEditorID(miscGroup, 'SEG_ExpertiseItem');
  if not Assigned(sourceRecord) then
    raise Exception.Create('Source record is absent on reopen');
  miscGroup := GroupBySignature(patchFile, 'MISC');
  if not Assigned(miscGroup) then
    raise Exception.Create('Patch MISC group is absent on reopen');
  if ElementCount(miscGroup) <> 1 then
    raise Exception.Create('Patch has more than one MISC override on reopen');
  patchRecord := MainRecordByEditorID(miscGroup, 'SEG_ExpertiseItem');
  if not Assigned(patchRecord) then
    raise Exception.Create('Patch override is absent on reopen');

  if GetElementEditValues(sourceRecord, 'FULL') <> 'SEG Expertise Token' then
    raise Exception.Create('Source value changed on disk');
  if GetElementEditValues(patchRecord, 'FULL') <> 'SEG Expertise Token - Patched' then
    raise Exception.Create('Patch value is wrong on reopen');
  winner := WinningOverride(sourceRecord);
  if not Assigned(winner) then
    raise Exception.Create('Override chain has no winner');
  if not SameText(GetFileName(GetFile(winner)), 'SEG_MinimalPatch.esp') then
    raise Exception.Create('Minimal patch is not the override winner');
  if not HasMaster(patchFile, 'SEG_CK_Practical3.esp') then
    raise Exception.Create('Patch lost its original-fixture master');

  AddMessage('SEG_PATCH_REOPEN_OK');
  AddMessage('source-editor-id=SEG_ExpertiseItem');
  AddMessage('source-full=SEG Expertise Token');
  AddMessage('winner-file=SEG_MinimalPatch.esp');
  AddMessage('winner-full=SEG Expertise Token - Patched');
  AddMessage('patch-misc-record-count=1');
  Result := 0;
end;

end.
