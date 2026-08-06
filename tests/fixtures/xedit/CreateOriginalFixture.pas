{
  Creates a disposable Skyrim SE fixture for Creation Kit round-trip
  validation. The generated binary is local-only and contains only newly
  constructed records. A CK reopen is still required before claiming that the
  blank package has a valid CK procedure tree.
}
unit CreateOriginalFixture;

function NewRecord(plugin: IInterface; sig, editorId: String): IInterface;
var
  recordGroup: IInterface;
begin
  recordGroup := GroupBySignature(plugin, sig);
  if not Assigned(recordGroup) then begin
    Add(plugin, sig, True);
    recordGroup := GroupBySignature(plugin, sig);
  end;
  Result := Add(recordGroup, sig, True);
  if not Assigned(Result) then
    raise Exception.Create('Could not create ' + sig + ' ' + editorId);
  SetElementEditValues(Result, 'EDID', editorId);
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
  i, j: Integer;
  skyrim, plugin, cellRecord, cellRef, actorRecord, dialogueRecord, infoRecord,
    questRecord, packageRecord,
    itemRecord, packages, packageEntry, items, itemEntry: IInterface;
  outputPath: String;
begin
  for i := 0 to Pred(FileCount) do
    if SameText(GetFileName(FileByIndex(i)), 'Skyrim.esm') then
      skyrim := FileByIndex(i);
  if not Assigned(skyrim) then
    raise Exception.Create('Skyrim.esm is not loaded');

  plugin := AddNewFileName('SEG_CK_Practical3.esp');
  if not Assigned(plugin) then
    raise Exception.Create('Could not create SEG_CK_Practical3.esp');
  AddMasterIfMissing(plugin, 'Skyrim.esm');

  itemRecord := NewRecord(plugin, 'MISC', 'SEG_ExpertiseItem');
  SetElementEditValues(itemRecord, 'FULL', 'SEG Expertise Token');
  Add(itemRecord, 'DATA', True);
  SetElementNativeValues(itemRecord, 'DATA\Value', 1);
  SetElementNativeValues(itemRecord, 'DATA\Weight', 0.1);

  { Do not clone a Bethesda record. This original shell deliberately receives
    no CK-validity credit until it is opened, configured, and saved in CK. }
  packageRecord := NewRecord(plugin, 'PACK', 'SEG_ExpertisePackage');

  actorRecord := NewRecord(plugin, 'NPC_', 'SEG_ExpertiseActor');
  SetElementEditValues(actorRecord, 'FULL', 'SEG Expertise Actor');
  Add(actorRecord, 'ACBS', True);
  SetElementNativeValues(actorRecord, 'ACBS\Speed Multiplier', 100);
  SetElementEditValues(actorRecord, 'RNAM',
    Name(RecordByFormID(skyrim, $00013746, True)));
  SetElementEditValues(actorRecord, 'CNAM',
    Name(RecordByFormID(skyrim, $0001326B, True)));
  packages := Add(actorRecord, 'Packages', True);
  if ElementCount(packages) > 0 then
    packageEntry := ElementByIndex(packages, 0)
  else
    packageEntry := ElementAssign(packages, HighInteger, nil, False);
  SetEditValue(packageEntry, Name(packageRecord));
  items := Add(actorRecord, 'Items', True);
  if ElementCount(items) > 0 then
    itemEntry := ElementByIndex(items, 0)
  else
    itemEntry := ElementAssign(items, HighInteger, nil, False);
  SetElementEditValues(itemEntry, 'CNTO\Item', Name(itemRecord));
  SetElementNativeValues(itemEntry, 'CNTO\Count', 1);

  questRecord := NewRecord(plugin, 'QUST', 'SEG_ExpertiseQuest');
  SetElementEditValues(questRecord, 'FULL', 'SEG Expertise Quest');
  Add(questRecord, 'DNAM', True);
  dialogueRecord := NewRecord(plugin, 'DIAL', 'SEG_ExpertiseDialogue');
  SetElementEditValues(dialogueRecord, 'QNAM', Name(questRecord));
  Add(dialogueRecord, 'DATA', True);
  SetElementEditValues(dialogueRecord, 'DATA\Category', 'Miscellaneous');
  SetElementEditValues(dialogueRecord, 'DATA\Subtype', 'SharedInfo');
  infoRecord := Add(dialogueRecord, 'INFO', True);
  if Assigned(infoRecord) then begin
    Add(infoRecord, 'ENAM', True);
    Add(infoRecord, 'CNAM', True);
    Add(infoRecord, 'Responses', True);
  end;

  cellRecord := NewRecord(plugin, 'CELL', 'SEG_ExpertiseCell');
  SetElementEditValues(cellRecord, 'FULL', 'SEG Expertise Cell');
  Add(cellRecord, 'DATA', True);
  SetElementNativeValues(cellRecord, 'DATA\Flags', 1);
  cellRef := Add(cellRecord, 'REFR', True);
  SetElementEditValues(cellRef, 'NAME', Name(itemRecord));
  Add(cellRef, 'DATA', True);

  outputPath := DataPath + 'SEG_CK_Practical3.esp';
  SavePlugin(plugin, outputPath);
  AddMessage('SEG disposable fixture saved: ' + outputPath);
  AddMessage('Original records: CELL/REFR, NPC_/item, DIAL/INFO, QUST, PACK, MISC');
end;

end.
