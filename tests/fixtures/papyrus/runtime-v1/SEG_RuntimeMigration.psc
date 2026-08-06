Scriptname SEG_RuntimeMigration extends Quest

Int Property SEGSchemaVersion = 1 Auto

Event OnInit()
    SEGSchemaVersion = 1
    Debug.Trace("SEG_EVENT_OK schema=1")
    Debug.Trace("SEG_MIGRATION_OLD schema=1")
    RegisterForSingleUpdate(5.0)
EndEvent

Event OnUpdate()
    Debug.Trace("SEG_MIGRATION_OLD schema=" + SEGSchemaVersion)
    RegisterForSingleUpdate(5.0)
EndEvent
