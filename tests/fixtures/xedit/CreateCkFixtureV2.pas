{
  Creates a disposable, local-only Skyrim SE fixture for Creation Kit
  validation. The binary is never committed or redistributed.
}
unit CreateCkFixtureV2;

function FirstMainRecord(e: IInterface): IInterface;
var
  i: Integer;
  child: IInterface;
  sig: String;
begin
  if not Assigned(e) then
    Exit;
  sig := Signature(e);
  if (sig <> '') and (sig <> 'GRUP') and (sig <> 'TES4') then begin
    Result := e;
    Exit;
  end;
  for i := 0 to Pred(ElementCount(e)) do begin
    child := FirstMainRecord(ElementByIndex(e, i));
    if Assigned(child) then begin
      Result := child;
      Exit;
    end;
  end;
end;

function FindTemplate(f: IInterface; sig, edid: String): IInterface;
var
  g: IInterface;
begin
  g := GroupBySignature(f, sig);
  if not Assigned(g) then
    Exit;
  Result := MainRecordByEditorID(g, edid);
  if not Assigned(Result) then
    Result := FirstMainRecord(g);
end;

function CopyAsOriginal(templateRecord, destination: IInterface;
  newEditorId: String): IInterface;
begin
  if not Assigned(templateRecord) then
    raise Exception.Create('Missing template for ' + newEditorId);
  AddRequiredElementMasters(templateRecord, destination, False);
  Result := wbCopyElementToFile(templateRecord, destination, True, True);
  if not Assigned(Result) then
    raise Exception.Create('Copy failed for ' + newEditorId);
  SetElementEditValues(Result, 'EDID', newEditorId);
end;

procedure SavePlugin(plugin: IInterface; outputPath: String);
var
  stream: TFileStream;
begin
  stream := TFileStream.Create(outputPath, fmCreate);
  try
    FileWriteToStream(plugin, stream, False);
  finally
    stream.Free;
  end;
end;

function Initialize: Integer;
var
  i: Integer;
  skyrim, plugin, cellRecord, actorRecord, dialogueRecord, questRecord,
    packageRecord, itemRecord, packages, packageEntry, items, itemEntry:
    IInterface;
  outputPath: String;
begin
  for i := 0 to Pred(FileCount) do
    if SameText(GetFileName(FileByIndex(i)), 'Skyrim.esm') then
      skyrim := FileByIndex(i);
  if not Assigned(skyrim) then
    raise Exception.Create('Skyrim.esm is not loaded');

  plugin := AddNewFileName('SEG_Expertise.esp');
  if not Assigned(plugin) then
    raise Exception.Create('Could not create SEG_Expertise.esp');
  AddMasterIfMissing(plugin, 'Skyrim.esm');

  itemRecord := CopyAsOriginal(
    FindTemplate(skyrim, 'MISC', 'Gold001'), plugin, 'SEG_ExpertiseItem');
  SetElementEditValues(itemRecord, 'FULL', 'SEG Expertise Token');

  packageRecord := CopyAsOriginal(
    FindTemplate(skyrim, 'PACK', 'DefaultSandboxEditorLocation512'),
    plugin, 'SEG_ExpertisePackage');

  actorRecord := CopyAsOriginal(
    FindTemplate(skyrim, 'NPC_', 'Alvor'), plugin, 'SEG_ExpertiseActor');
  SetElementEditValues(actorRecord, 'FULL', 'SEG Expertise Actor');
  packages := ElementByName(actorRecord, 'Packages');
  if Assigned(packages) and (ElementCount(packages) > 0) then begin
    packageEntry := ElementByIndex(packages, 0);
    SetEditValue(packageEntry, Name(packageRecord));
  end;
  items := ElementByName(actorRecord, 'Items');
  if Assigned(items) and (ElementCount(items) > 0) then begin
    itemEntry := ElementByIndex(items, 0);
    SetElementEditValues(itemEntry, 'CNTO\Item', Name(itemRecord));
    SetElementNativeValues(itemEntry, 'CNTO\Count', 1);
  end;

  questRecord := CopyAsOriginal(
    FindTemplate(skyrim, 'QUST', 'DialogueFollower'),
    plugin, 'SEG_ExpertiseQuest');
  SetElementEditValues(questRecord, 'FULL', 'SEG Expertise Quest');
  RemoveElement(questRecord, 'VMAD');

  dialogueRecord := CopyAsOriginal(
    FindTemplate(skyrim, 'DIAL', 'DialogueFollowerTopic'),
    plugin, 'SEG_ExpertiseDialogue');
  SetElementEditValues(dialogueRecord, 'QNAM', Name(questRecord));

  cellRecord := Add(plugin, 'CELL', True);
  if not Assigned(cellRecord) then
    raise Exception.Create('Could not create SEG_ExpertiseCell');
  SetElementEditValues(cellRecord, 'EDID', 'SEG_ExpertiseCell');
  SetElementEditValues(cellRecord, 'FULL', 'SEG Expertise Cell');

  outputPath := DataPath + 'SEG_Expertise.esp';
  SavePlugin(plugin, outputPath);
  AddMessage('SEG fixture saved: ' + outputPath);
  AddMessage('SEG records: CELL, NPC_, DIAL/INFO, QUST/stages, PACK, MISC, VMAD');
end;

end.
