Scriptname SEG_RuntimeMigration extends Quest

Int Property SEGSchemaVersion = 1 Auto

Event OnInit()
    SEGSchemaVersion = 2
    Debug.Trace("SEG_EVENT_OK schema=2")
EndEvent

Event OnUpdate()
    If SEGSchemaVersion == 1
        SEGSchemaVersion = 2
        Debug.Trace("SEG_MIGRATION_NEW from=1 to=2")
    EndIf
EndEvent
