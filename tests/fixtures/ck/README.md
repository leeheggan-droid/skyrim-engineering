# Creation Kit fixture evidence

The retained xDump transcript describes the earlier disposable
`SEG_CK_Practical3.esp`. That run is not release evidence because its package
was copied from a Bethesda master. The generator has since been corrected to
create an original blank `PACK`; no plugin binary is committed.

Verified records: one miscellaneous item, one NPC, one interior cell and placed
reference, one dialogue topic/info pair, one quest with stage 10 and the
`SEG_ValidEvent` VMAD attachment, and one package assigned to the NPC. The
earlier package is Bethesda-derived. No alias, objective, package condition, or
navmesh was present; those rubric elements receive no credit. The corrected
original package shell has not yet passed a CK reopen and receives no CK
round-trip credit. A replacement practical must configure and save its procedure
tree in CK, then repeat the xDump check before this domain can pass.

Rollback is deletion of the disposable plugin and data directory. No save was
opened and no installed game file was modified. The four licensed masters used
only for validation were copied to the disposable directory, hash-checked, and
removed after xDump completed.
