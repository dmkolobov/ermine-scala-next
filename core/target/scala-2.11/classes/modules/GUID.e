module GUID where

foreign -- data "java.util.UUID" GUID -- builtin now
        function "java.util.UUID" "randomUUID" guid : IO GUID
        method "toString" guidString : GUID -> String
        function "java.util.UUID" "fromString" stringGuid : String -> GUID

