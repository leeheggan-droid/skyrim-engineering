{
  Creates exactly one override of the original SEG_ExpertiseItem fixture.
  The source fixture and output patch must be in an isolated Data directory.
}
unit CreateMinimalPatch;

procedure SavePlugin(plugin: IInterface; outputPath: String);
var
  stream: TFileStream;
begin
  stream := TFileStream.Create(outputPath, fmCreate);
  try
    FileWriteToStream(plugin, stream, True);
  finally
    stream.Free;
  end;
end;

function Initialize: Integer;
var
  i: Integer;
  sourceFile, patchFile, sourceRecord, patchRecord, miscGroup: IInterface;
  outputPath: String;
begin
  Result := 1;
  for i := 0 to Pred(FileCount) do
    if SameText(GetFileName(FileByIndex(i)), 'SEG_CK_Practical3.esp') then
      sourceFile := FileByIndex(i);
  if not Assigned(sourceFile) then
    raise Exception.Create('SEG_CK_Practical3.esp is not loaded');

  outputPath := DataPath + 'SEG_MinimalPatch.esp';
  if FileExists(outputPath) then
    raise Exception.Create('Refusing to overwrite existing SEG_MinimalPatch.esp');

  miscGroup := GroupBySignature(sourceFile, 'MISC');
  if not Assigned(miscGroup) then
    raise Exception.Create('Source fixture has no MISC group');
  sourceRecord := MainRecordByEditorID(miscGroup, 'SEG_ExpertiseItem');
  if not Assigned(sourceRecord) then
    raise Exception.Create('Source fixture has no SEG_ExpertiseItem');
  if GetElementEditValues(sourceRecord, 'FULL') <> 'SEG Expertise Token' then
    raise Exception.Create('Source fixture display name is not the reviewed original value');

  patchFile := AddNewFileName('SEG_MinimalPatch.esp');
  if not Assigned(patchFile) then
    raise Exception.Create('Could not create SEG_MinimalPatch.esp');
  patchRecord := wbCopyElementToFile(sourceRecord, patchFile, False, True);
  if not Assigned(patchRecord) then
    raise Exception.Create('Could not copy SEG_ExpertiseItem as override');
  SetElementEditValues(patchRecord, 'FULL', 'SEG Expertise Token - Patched');
  CleanMasters(patchFile);

  if GetElementEditValues(sourceRecord, 'FULL') <> 'SEG Expertise Token' then
    raise Exception.Create('Patch creation changed the source record');
  if GetElementEditValues(patchRecord, 'FULL') <> 'SEG Expertise Token - Patched' then
    raise Exception.Create('Patch override value did not persist in memory');
  if ElementCount(GroupBySignature(patchFile, 'MISC')) <> 1 then
    raise Exception.Create('Patch does not contain exactly one MISC override');
  if not HasMaster(patchFile, 'SEG_CK_Practical3.esp') then
    raise Exception.Create('Patch does not name the original fixture as a master');

  SavePlugin(patchFile, outputPath);
  AddMessage('SEG_PATCH_CREATE_OK');
  AddMessage('source-editor-id=SEG_ExpertiseItem');
  AddMessage('source-full=SEG Expertise Token');
  AddMessage('patch-full=SEG Expertise Token - Patched');
  AddMessage('patch-misc-record-count=1');
  Result := 0;
end;

end.
