# Creation Kit fixture evidence

The retained xDump transcript describes the earlier disposable
`SEG_CK_Practical3.esp`. That run is not release evidence because its package
was copied from a Bethesda master. The generator has since been corrected to
create an original blank `PACK`; no plugin binary is committed.

Historically observed, not qualified: one miscellaneous item, one NPC, one
interior cell and placed reference, one dialogue topic/info pair, one quest with
stage 10 and the `SEG_ValidEvent` VMAD attachment, and one package assigned to
the NPC. The earlier package is Bethesda-derived. No alias, objective, package
condition, or navmesh was present; those rubric elements receive no credit. The
corrected original package shell has not yet passed a CK reopen and receives no
CK round-trip credit.

Use `Prepare-CkQualification.ps1` to create a `PREPARED` runbook without
launching Creation Kit only when an approved defect requires CK evidence. This
blocked track is on demand, not a prerequisite to multiplayer work or the v1
release. A human must then configure the original quest alias,
stage/objective, CTDA conditions, record relationships, package procedure tree,
and owned finalized navmesh; save the active plugin; fully close CK; reopen,
inspect, save, and close; and obtain a named independent review. The private
submission binds tool, seed/save/reopen, master, INI, structured record, and raw
xDump hashes. `Test-CkCapture.ps1` checks both xDump exits and can emit only a
sanitized `UNVERIFIED_SUBMISSION`; it never promotes the track to verified.

Rollback is deletion of the disposable plugin and data directory. No save was
opened and no installed game file was modified. The four licensed masters used
only for validation were copied to the disposable directory, hash-checked, and
removed after xDump completed.
