 
 /*------------------------------------------------------------------------
    File        : Jsonifier
    Purpose     : Create JSON debugging output based on a handle or an object.
    Syntax      : 
                    See test_Jsonifier for examples.
                    Basically you use a static call like:
                        
                        oJsonOut = Jsonifier.Jsonify(oSomeobject)
                        or
                        oJsonOut = Jsonifier.Jsonify(hHandle)
                    
                    Then use oJsonOut:WriteFile() to create a JSON representation
                    of the object and its properties/children for debugging purposes.
    Description : 
    Author(s)   : S.E. Southwell
    Created     : Mon Dec 23 10:40:23 CST 2024
    Notes       : 
        1. This currently has no method to prevent circular references from blowing the stack.
        
    To do       :
        1. Handle circular references.  e.g.: Class A has an attribute for Class B, which has an attribute
            referring back to Class A.
        2. Go back through all the various handle types and make sure we got all the attributes and methods 
            that exist.
  ----------------------------------------------------------------------*/


BLOCK-LEVEL ON ERROR UNDO, THROW.

USING Progress.Json.ObjectModel.JsonArray FROM PROPATH.
USING Progress.Json.ObjectModel.JsonObject FROM PROPATH.
USING Progress.Lang.Object FROM PROPATH.
USING system.ExtentHelper FROM PROPATH.
USING Progress.Lang.AppError FROM PROPATH.

CLASS system.Jsonifier USE-WIDGET-POOL: 
    DEFINE STREAM tempstream.
    DEFINE STATIC TEMP-TABLE ttUnhandled NO-UNDO
        FIELD attrName AS CHARACTER
        INDEX pkattrName IS PRIMARY UNIQUE attrname.
    
    DEFINE STATIC TEMP-TABLE ttObject NO-UNDO
        FIELD typeName AS CHARACTER
        FIELD objHdl   AS Progress.Lang.Object.
    
    // DetailLevel:
        // 1: Just show the name and value of object properties.
        // 2: Provide a little more info about the property 
        // 3: Full info about the property
    DEFINE PUBLIC STATIC PROPERTY DetailLevel AS INTEGER INIT 3 NO-UNDO GET. SET. 
    
    DEFINE PUBLIC STATIC PROPERTY IncludeObjects AS LOGICAL INIT FALSE GET. SET.
    DEFINE PUBLIC STATIC PROPERTY IncludeProcs   AS LOGICAL INIT FALSE GET. SET.

	/*------------------------------------------------------------------------------
	 Purpose:
	 Notes:
	------------------------------------------------------------------------------*/

	CONSTRUCTOR STATIC Jsonifier (  ):
		
	END CONSTRUCTOR.


    /*------------------------------------------------------------------------------
     Purpose:
     Notes:
    ------------------------------------------------------------------------------*/

    METHOD PUBLIC STATIC VOID DumpUnhandled(  ):
        OUTPUT STREAM tempstream TO VALUE("testoutput/notdone.txt").
        FOR EACH ttUnhandled:
            PUT STREAM tempstream
                UNFORMATTED
                SUBSTITUTE("~t~t~t~tWHEN ~"&1~" THEN oJsonObject:Add(~"&1~",hObj:&1) NO-ERROR.",ttUnhandled.attrName)
                SKIP.
        END.

        OUTPUT STREAM tempstream CLOSE.
    END METHOD.

    /*------------------------------------------------------------------------------
     Purpose:
     Notes:
    ------------------------------------------------------------------------------*/

    METHOD STATIC JsonObject Jsonify(
        INPUT oObj AS Progress.Lang.Object
    ):
        DEFINE VARIABLE oJsonObject AS JsonObject NO-UNDO.
        DEFINE VARIABLE oClass AS Progress.Lang.Class NO-UNDO.
        DEFINE VARIABLE oProps AS Progress.Reflect.Property EXTENT NO-UNDO.
        DEFINE VARIABLE iCount AS INTEGER NO-UNDO.
        DEFINE VARIABLE oPropJson AS JsonObject NO-UNDO.
        DEFINE VARIABLE oPropObj AS Object NO-UNDO.
        DEFINE VARIABLE oValueArray AS JsonArray NO-UNDO.
        DEFINE VARIABLE iThisExtent AS INTEGER NO-UNDO.
        DEFINE VARIABLE iPropExtentCount AS INTEGER NO-UNDO.
        DEFINE VARIABLE cThisCharValue AS CHARACTER NO-UNDO.

        oJsonObject = NEW JsonObject().
        oClass = oObj:GetClass() NO-ERROR.
        oJsonObject:Add("TypeName", oClass:TypeName) NO-ERROR.
        
        IF ERROR-STATUS:ERROR THEN DO:
            oJsonObject:ADD("TypeName","invalidObject").
            RETURN oJsonObject.
        END.

        oProps = oClass:GetProperties().
        DO iCount = 1 TO EXTENT(oProps):
            // Exceptions we can't deal with due to bugs in ABL:
            IF CAN-DO("ContextNames,PathParameterNames",oProps[iCount]:Name) AND oClass:TypeName =  "OpenEdge.Web.WebRequest"
                THEN DO:
                oJsonObject:Add(oProps[iCount]:name,"[unable to obtain due to ABL bug]").   
                NEXT.    
            END.

            IF CAN-DO("NEXT-SIBLING,PREV-SIBLING", oProps[iCount]:Name) THEN NEXT.
            iThisExtent = oProps[iCount]:Extent.
            IF iThisExtent = ? THEN iThisExtent = ExtentHelper:GetExtent(oObj,oProps[iCount]:NAME).

            CASE DetailLevel:
                WHEN 1 THEN DO: // Value only
                   CASE oProps[iCount]:DataType:
                        WHEN Progress.Reflect.DataType:Object 
                            THEN DO:
                            oPropObj = DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name) NO-ERROR.
                            IF ERROR-STATUS:ERROR THEN NEXT.
                            IF CAN-DO("NEXT-SIBLING,PREV-SIBLING", oProps[iCount]:Name) THEN NEXT.
                                //oJsonObject:Add(oProps[iCount]:Name,oPropObj:GetClass():TypeName) NO-ERROR.
                            ELSE       
                                oJsonObject:Add(oProps[iCount]:Name, Jsonify(oPropObj)) NO-ERROR.
                        END.
                        WHEN Progress.Reflect.DataType:COMHandle OR
                        WHEN Progress.Reflect.DataType:TableHandle OR
                        WHEN Progress.Reflect.DataType:DataSetHandle OR
                        WHEN Progress.Reflect.DataType:Handle 
                            THEN oJsonObject:Add(oProps[iCount]:Name, Jsonify(DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name))).   
                        WHEN Progress.Reflect.DataType:Memptr
                            THEN oJsonObject:Add(oProps[iCount]:Name,"[memptr]").
                        OTHERWISE DO:
                            IF iThisExtent = 0 THEN oJsonObject:Add(oProps[iCount]:Name, DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name)) NO-ERROR.
                            ELSE IF IThisExtent = ? THEN oJsonObject:Add(oProps[iCount]:NAME,"UnfixedExtent").
                            ELSE DO:
                                oValueArray =  NEW JsonArray().
                                DO iPropExtentCount = 1 TO iThisExtent:
                                    oValueArray:Add(DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name,iPropExtentCount)).
                                END.
                                oJsonObject:Add(oProps[iCount]:Name,oValueArray).
                            END.
                        END.
                    END CASE.
                    
                END.
                WHEN 2 OR WHEN 3 THEN DO:
                    oPropJson = NEW JsonObject().
                    IF DetailLevel = 3 THEN DO: // 3 = very detailed
                        oPropJson:Add("AccessMode", oProps[iCount]:AccessMode:ToString()).
                        oPropJson:Add("DataType", oProps[iCount]:DataType:ToString()).
                        IF oProps[iCount]:DataTypeName NE ? THEN 
                            oPropJson:Add("DataTypeName", oProps[iCount]:DataTypeName).
                        IF iThisExtent NE 0 THEN oPropJson:Add("Extent",iThisExtent).
                    END.
                    ELSE DO: // 2 = a little detail
                        oPropJson:Add("PropertyInfo",TRIM(SUBSTITUTE("&1 &2 &3",
                                                            oProps[iCount]:AccessMode:ToString(),
                                                            oProps[iCount]:DataType:ToString(),
                                                            (IF oProps[iCount]:Extent > 0 
                                                            THEN STRING(oProps[iCount]:Extent) ELSE "")
                                                          ))).
                    END.

                    CASE oProps[iCount]:DataType:
                        WHEN Progress.Reflect.DataType:Object 
                            THEN DO:
                                IF iThisExtent = 0 THEN DO:
                                    oPropObj = DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name) NO-ERROR.
                                    IF ERROR-STATUS:ERROR THEN NEXT.
                                    IF CAN-DO("NEXT-SIBLING,PREV-SIBLING", oProps[iCount]:Name) THEN NEXT.
                                        //oPropJson:Add("Value",oPropObj:GetClass():TypeName) NO-ERROR.
                                    ELSE       
                                        oPropJson:Add("Value", Jsonify(oPropObj)) NO-ERROR.
                                END. // no extent
                                ELSE IF iThisExtent = ? THEN oPropJson:Add("Value","UnfixedExtent").
                                ELSE DO:
                                    oValueArray = NEW JsonArray().
                                    DO iPropExtentCount = 1 TO iThisExtent:
                                        oValueArray:Add(Jsonify(DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name,iPropExtentCount))).
                                    END.
                                    oPropJson:Add("Value",oValueArray).
                                    DELETE OBJECT oValueArray.
                                END.
                        END. // Object
                        WHEN Progress.Reflect.DataType:COMHandle OR
                        WHEN Progress.Reflect.DataType:TableHandle OR
                        WHEN Progress.Reflect.DataType:DataSetHandle OR
                        WHEN Progress.Reflect.DataType:Handle 
                            THEN oPropJson:Add("Value", Jsonify(DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name))).   
                        WHEN Progress.Reflect.DataType:Memptr
                            THEN oJsonObject:Add("Value","[memptr]").
                        OTHERWISE DO ON ERROR UNDO, NEXT: // Primative type
                            IF iThisExtent = 0 THEN oPropJson:Add("Value", DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name)) NO-ERROR.
                            ELSE IF iThisExtent = ? THEN oPropJson:Add("Value","UnfixedExtent").
                            ELSE DO:
                                oValueArray = NEW JsonArray().
                                DO iPropExtentCount = 1 TO iThisExtent:
                                    oValueArray:Add(DYNAMIC-PROPERTY(oObj,oProps[iCount]:Name,iPropExtentCount)).
                                END.
                                oPropJson:Add("Value",oValueArray).
                            END.
                            CATCH E AS Progress.Lang.Error :
                                MESSAGE "CAUGHT" e:GetMessage(1). 
                            END CATCH.
                        END.
                    END CASE.
                    
                    oJsonObject:Add(oProps[iCount]:Name,oPropJson).
                END. // 3
            END CASE.
        END.
        
        IF oClass:isA("Progress.Json.ObjectModel.JsonObject") 
            THEN DO:
            oJsonObject:Add("JSON", CAST(oObj,"Progress.Json.ObjectModel.JsonObject")).
        END.
        
        IF oClass:IsA("Progress.Lang.AppError") THEN DO:
            oValueArray = NEW JsonArray().
            DO iCount = 1 TO DYNAMIC-PROPERTY(oObj,"NumMessages"):
                oPropJson = NEW JsonObject().
                oPropJson:Add("MessageNum",DYNAMIC-INVOKE(oObj,"GetMessageNum",iCount)).
                oPropJson:Add("Message",DYNAMIC-INVOKE(oObj,"GetMessage",iCount)).
                oValueArray:Add(oPropJson).
            END.
            oJsonObject:Add("messages",oValueArray).
        END.
        
        RETURN oJsonObject.        
    END.

    METHOD STATIC JsonObject Jsonify(
        INPUT hObj AS HANDLE
    ):
        DEFINE VARIABLE oJsonObject AS JsonObject NO-UNDO.
        DEFINE VARIABLE oSubJson    AS JsonObject NO-UNDO.
        DEFINE VARIABLE cAttrList   AS CHARACTER NO-UNDO.
        DEFINE VARIABLE iCount      AS INTEGER NO-UNDO.
        DEFINE VARIABLE cThisAttr   AS CHARACTER NO-UNDO.
        DEFINE VARIABLE oObjects    AS JsonArray NO-UNDO.
        DEFINE VARIABLE oThisObj    AS Progress.Lang.Object NO-UNDO.
        DEFINE VARIABLE cPropList   AS CHARACTER NO-UNDO.
        DEFINE VARIABLE cMethodList AS CHARACTER NO-UNDO.
        DEFINE VARIABLE hSubObj     AS HANDLE    NO-UNDO.
        
        oJsonObject = NEW JsonObject().
        IF NOT VALID-HANDLE(hObj) THEN DO:
            oJsonObject:Add("TYPE","invalidHandle").
            RETURN oJsonObject.
        END.
        
        oJsonObject:Add("TYPE",hObj:TYPE).
        oJsonObject:Add("NAME",hObj:NAME) NO-ERROR. // Most but not all handles have a name.  CP doesn't
        
        cAttrList = LIST-QUERY-ATTRS(hObj).
        
        // Try to put some important things near the top.
        // Whatever isn't specifically in the case can be picked up in the section below.
        CASE hObj:TYPE:
            WHEN "BUFFER" THEN DO:
                oObjects = NEW JsonArray().
                DO iCount = 1 TO hObj:NUM-FIELDS:
                    IF DetailLevel >= 3 THEN oObjects:Add(Jsonify(hObj:BUFFER-FIELD(iCount))).
                    ELSE oObjects:Add(hObj:BUFFER-FIELD(iCount):NAME).
                END.
                oJsonObject:Add("BUFFER-FIELDS",oObjects).
            END. // BUFFER 
            WHEN "CLIENT-PRINCIPAL" THEN DO:               
                oJsonObject:Add("AUDIT-EVENT-CONTEXT",hObj:AUDIT-EVENT-CONTEXT).       
                oJsonObject:Add("CLIENT-TTY",hObj:CLIENT-TTY).
                oJsonObject:Add("CLIENT-WORKSTATION",hObj:CLIENT-WORKSTATION).
                oJsonObject:Add("DB-LIST",hObj:DB-LIST).
                oJsonObject:Add("DOMAIN-DESCRIPTION",hObj:DOMAIN-DESCRIPTION).
                oJsonObject:Add("DOMAIN-NAME",hObj:DOMAIN-NAME).
                oJsonObject:Add("DOMAIN-TYPE",hObj:DOMAIN-TYPE).
                oJsonObject:Add("LOGIN-EXPIRATION-TIMESTAMP",hObj:LOGIN-EXPIRATION-TIMESTAMP).
                oJsonObject:Add("LOGIN-HOST",hObj:LOGIN-HOST).
                oJsonObject:Add("LOGIN-STATE",hObj:LOGIN-STATE).
                //oJsonObject:Add("PRIMARY-PASSPHRASE",hObj:PRIMARY-PASSPHRASE).
                oJsonObject:Add("QUALIFIED-USER-ID",hObj:QUALIFIED-USER-ID).
                oJsonObject:Add("ROLES",hObj:ROLES).
                oJsonObject:Add("SEAL-TIMESTAMP",hObj:SEAL-TIMESTAMP).
                oJsonObject:Add("SESSION-ID",hObj:SESSION-ID).
                oJsonObject:Add("STATE-DETAIL",hObj:STATE-DETAIL).
                oJsonObject:Add("USER-ID",hObj:USER-ID).
                // Loop through properties:
                cPropList = hObj:LIST-PROPERTY-NAMES().
                oSubJson = NEW JsonObject().
                DO iCount = 1 TO NUM-ENTRIES(cPropList):
                    oSubJson:Add(ENTRY(iCount,cPropList), hObj:GET-PROPERTY (ENTRY(iCount,cPropList))).
                END.       
                oJsonObject:Add("PROPERTIES",oSubJson).   
            END. // CLIENT-PRINCIPAL
            WHEN "DATASET" THEN DO:         
                oJsonObject:Add("DATA-SOURCE-MODIFIED",hObj:DATA-SOURCE-MODIFIED).
                oJsonObject:Add("DYMAMIC",hObj:DYNAMIC).
                oJsonObject:Add("NAMESPACE-PRIFIX",hObj:NAMESPACE-PREFIX).
                oJsonObject:Add("NAMESPACE-URI",hObj:NAMESPACE-URI).
                oJsonObject:Add("NEXT-SIBLING",hObj:NEXT-SIBLING).
                oJsonObject:Add("NUM-BUFFERS",hObj:NUM-BUFFERS).
                oJsonObject:Add("NUM-REFERENCES",hObj:NUM-REFERENCES).
                oJsonObject:Add("NUM-RELATIONS",hObj:NUM-RELATIONS).
                oJsonObject:Add("NUM-TOP-BUFFERS",hObj:NUM-TOP-BUFFERS).
                oJsonObject:Add("REJECTED",hObj:REJECTED).
                oJsonObject:Add("RELATIONS-ACTIVE",hObj:RELATIONS-ACTIVE).
                oJsonObject:Add("SERIALIZE-NAME",hObj:SERIALIZE-NAME).
                oJsonObject:Add("TOP-NAV-QUERY",hObj:TOP-NAV-QUERY).
                oJsonObject:Add("XML-NODE-NAME",hObj:XML-NODE-NAME).
                oJsonObject:Add("XML-NODE-TYPE",hObj:XML-NODE-TYPE).
                oSubJson = NEW JsonObject().     
                hObj:WRITE-JSON("JsonObject",oSubJson,TRUE).
                oJsonObject:Add("WRITE-JSON",oSubJson).
                
                oObjects = NEW JsonArray().
                IF detailLevel >= 2 THEN DO:
                    DO iCount = 1 TO hObj:NUM-BUFFERS:
                        oObjects:Add(Jsonify(hObj:GET-BUFFER-HANDLE(iCount))).
                    END.
                END.
                ELSE DO:
                    DO iCount = 1 TO hObj:NUM-BUFFERS:
                        oSubJson = NEW JsonObject().
                        oObjects:Add(hObj:GET-BUFFER-HANDLE(iCount):NAME).
                    END.         
                END.
                oJsonObject:Add("BUFFERS",oObjects).
            END. // DATASET
            WHEN "PSEUDO-WIDGET" THEN DO: // SESSION hdl
                // Loop all the objects
                IF IncludeObjects THEN DO:
                    EMPTY TEMP-TABLE ttObject.
                    oThisObj = hObj:FIRST-OBJECT.
                    DO WHILE oThisObj NE ?:
                        CREATE ttObject.
                        ASSIGN
                            ttObject.objHdl = oThisObj
                            ttObject.typeName = oThisObj:GetClass():TypeName.
                        oThisObj = oThisObj:NEXT-SIBLING.                   
                    END.   
                     
                    oObjects = NEW JsonArray().
                    FOR EACH ttObject:
                        IF ttObject.objHdl NE oJsonObject THEN
                        oObjects:Add(Jsonify(ttObject.objHdl)).
                    END. 
                    oJsonObject:Add("Objects",oObjects).
                    EMPTY TEMP-TABLE ttObject.     
                END.   
                // Loop all the procedures
                IF IncludeProcs THEN DO:
                    oObjects = NEW JsonArray().
                    DO iCount = 1 TO NUM-ENTRIES(hObj:SUPER-PROCEDURES):
                        hSubObj = HANDLE(ENTRY(iCount,hObj:SUPER-PROCEDURES)).
                        oObjects:Add(Jsonify(hSubObj)).
                    END.
                    oJsonObject:Add("SUPER-PROCEDURES",oObjects).
                    
                    oObjects = NEW JsonArray().
                    hSubObj = hObj:FIRST-PROCEDURE.
                    DO WHILE hSubObj NE ?:
                        oObjects:ADD(Jsonify(hSubObj)).
                        hSubObj = hObj:NEXT-SIBLING.
                    END.
                    oJsonObject:Add("PROCEDURES",oObjects).
                END.
                 
            END.
            OTHERWISE DO:
            END.
        END CASE.

        // All the rest of the handle attributes we don't have in the JSON yet
        DO iCount = 1 TO NUM-ENTRIES(cAttrList):
            cThisAttr = ENTRY(iCount,cAttrList).
            IF oJsonObject:Has(cThisAttr) THEN NEXT.
            CASE cThisAttr:
            // PROPERTIES - There is no dynamic way to reference a handle prop in ABL, so this big stupid
            //              list is how you do it.
                WHEN "ADM-DATA" THEN oJsonObject:Add("ADM-DATA",hObj:ADM-DATA) NO-ERROR.
                WHEN "APPL-ALERT-BOXES" THEN oJsonObject:Add("APPL-ALERT-BOXES",hObj:APPL-ALERT-BOXES) NO-ERROR.
                WHEN "AFTER-BUFFER" THEN oJsonObject:Add("AFTER-BUFFER",hObj:AFTER-BUFFER) NO-ERROR.
                WHEN "AFTER-ROWID" THEN oJsonObject:Add("AFTER-ROWID",hObj:AFTER-ROWID) NO-ERROR.
                WHEN "AMBIGUOUS" THEN oJsonObject:Add("AMBIGUOUS",hObj:AMBIGUOUS) NO-ERROR.
                WHEN "APPLY-CALLBACK" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "ASYNC-REQUEST-COUNT" THEN oJsonObject:Add("ASYNC-REQUEST-COUNT",hObj:ASYNC-REQUEST-COUNT) NO-ERROR.
                WHEN "ATTACH-DATA-SOURCE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "ATTACHED-PAIRLIST" THEN oJsonObject:Add("ATTACHED-PAIRLIST",hObj:ATTACHED-PAIRLIST) NO-ERROR.
                WHEN "AUTO-DELETE" THEN oJsonObject:Add("AUTO-DELETE",hObj:AUTO-DELETE) NO-ERROR.
                WHEN "AUTO-SYNCHRONIZE" THEN oJsonObject:Add("AUTO-SYNCHRONIZE",hObj:AUTO-SYNCHRONIZE) NO-ERROR.
                WHEN "AUTHENTICATION-FAILED" THEN oJsonObject:Add("AUTHENTICATION-FAILED",hObj:AUTHENTICATION-FAILED) NO-ERROR.
                WHEN "AVAILABLE" THEN oJsonObject:Add("AVAILABLE",hObj:AVAILABLE) NO-ERROR.
                WHEN "BASE-ADE" THEN oJsonObject:Add("BASE-ADE",hObj:BASE-ADE) NO-ERROR.
                WHEN "BASIC-LOGGING" THEN oJsonObject:Add("BASIC-LOGGING",hObj:BASIC-LOGGING) NO-ERROR.
                WHEN "BATCH-MODE" THEN oJsonObject:Add("BATCH-MODE",hObj:BATCH-MODE) NO-ERROR.
                WHEN "BATCH-SIZE" THEN oJsonObject:Add("BATCH-SIZE",hObj:BATCH-SIZE) NO-ERROR.
                WHEN "BEFORE-BUFFER" THEN oJsonObject:Add("BEFORE-BUFFER",hObj:BEFORE-BUFFER) NO-ERROR.
                WHEN "BEFORE-ROWID" THEN oJsonObject:Add("BEFORE-ROWID",hObj:BEFORE-ROWID) NO-ERROR.
                WHEN "BUFFER-COMPARE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-COPY" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-CREATE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-DELETE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-EXPORT" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-EXPORT-FIELDS" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-FIELD" THEN oJsonObject:Add("BUFFER-FIELD",hObj:BUFFER-FIELD) NO-ERROR.
                WHEN "BUFFER-GROUP-ID" THEN oJsonObject:Add("BUFFER-GROUP-ID",hObj:BUFFER-GROUP-ID) NO-ERROR.
                WHEN "BUFFER-GROUP-NAME" THEN oJsonObject:Add("BUFFER-GROUP-NAME",hObj:BUFFER-GROUP-NAME) NO-ERROR.
                WHEN "BUFFER-HANDLE" THEN oJsonObject:Add("BUFFER-HANDLE",hObj:BUFFER-HANDLE) NO-ERROR.
                WHEN "BUFFER-IMPORT" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-IMPORT-FIELDS" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                WHEN "BUFFER-NAME" THEN oJsonObject:Add("BUFFER-NAME",hObj:BUFFER-NAME) NO-ERROR.
                WHEN "BUFFER-PARTITION-ID" THEN oJsonObject:Add("BUFFER-PARTITION-ID",hObj:BUFFER-PARTITION-ID) NO-ERROR.
                WHEN "BUFFER-RELEASE" THEN oJsonObject:Add("BUFFER-RELEASE",hObj:BUFFER-RELEASE) NO-ERROR.
                WHEN "BUFFER-TENANT-ID" THEN oJsonObject:Add("BUFFER-TENANT-ID",hObj:BUFFER-TENANT-ID) NO-ERROR.
                WHEN "BUFFER-TENANT-NAME" THEN oJsonObject:Add("BUFFER-TENANT-NAME",hObj:BUFFER-TENANT-NAME) NO-ERROR.
                WHEN "BUFFER-VALIDATE" THEN oJsonObject:Add("BUFFER-VALIDATE",hObj:BUFFER-VALIDATE) NO-ERROR.
                WHEN "BUFFER-VALUE" THEN oJsonObject:Add("BUFFER-VALUE",hObj:BUFFER-VALUE) NO-ERROR.
                WHEN "BYTES-READ" THEN oJsonObject:Add("BYTES-READ",hObj:BYTES-READ) NO-ERROR.
                WHEN "BYTES-WRITTEN" THEN oJsonObject:Add("BYTES-WRITTEN",hObj:BYTES-WRITTEN) NO-ERROR.
                WHEN "CAN-CREATE" THEN oJsonObject:Add("CAN-CREATE",hObj:CAN-CREATE) NO-ERROR.
                WHEN "CAN-DELETE" THEN oJsonObject:Add("CAN-DELETE",hObj:CAN-DELETE) NO-ERROR.
                WHEN "CAN-READ" THEN oJsonObject:Add("CAN-READ",hObj:CAN-READ) NO-ERROR.
                WHEN "CAN-WRITE" THEN oJsonObject:Add("CAN-WRITE",hObj:CAN-WRITE) NO-ERROR.
                WHEN "CASE-SENSITIVE" THEN oJsonObject:Add("CASE-SENSITIVE",hObj:CASE-SENSITIVE) NO-ERROR.
                WHEN "COLUMN-LABEL" THEN oJsonObject:Add("COLUMN-LABEL",hObj:COLUMN-LABEL) NO-ERROR.
                WHEN "COPY-DATASET" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "COPY-TEMP-TABLE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "CRC-VALUE" THEN oJsonObject:Add("CRC-VALUE",hObj:CRC-VALUE) NO-ERROR.
                WHEN "CREATE-LIKE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "CREATE-RESULT-LIST-ENTRY" THEN oJsonObject:Add("CREATE-RESULT-LIST-ENTRY",hObj:CREATE-RESULT-LIST-ENTRY) NO-ERROR.
                WHEN "CURRENT-CHANGED" THEN oJsonObject:Add("CURRENT-CHANGED",hObj:CURRENT-CHANGED) NO-ERROR.
                WHEN "CURRENT-ITERATION" THEN oJsonObject:Add("CURRENT-ITERATION",hObj:CURRENT-ITERATION) NO-ERROR.
                WHEN "CACHE" THEN oJsonObject:Add("CACHE",hObj:CACHE) NO-ERROR.
                WHEN "CHARSET" THEN oJsonObject:Add("CHARSET",hObj:CHARSET) NO-ERROR.
                WHEN "CLEAR" THEN oJsonObject:Add("CLEAR",hObj:CLEAR) NO-ERROR.
                WHEN "CLIENT-TYPE" THEN oJsonObject:Add("CLIENT-TYPE",hObj:CLIENT-TYPE) NO-ERROR.
                WHEN "CONTEXT-HELP-FILE" THEN oJsonObject:Add("CONTEXT-HELP-FILE",hObj:CONTEXT-HELP-FILE) NO-ERROR.
                WHEN "CPCASE" THEN oJsonObject:Add("CPCASE",hObj:CPCASE) NO-ERROR.
                WHEN "CPCOLL" THEN oJsonObject:Add("CPCOLL",hObj:CPCOLL) NO-ERROR.
                WHEN "CPLOG" THEN oJsonObject:Add("CPLOG",hObj:CPLOG) NO-ERROR.
                WHEN "CPPRINT" THEN oJsonObject:Add("CPPRINT",hObj:CPPRINT) NO-ERROR.
                WHEN "CPRCODEIN" THEN oJsonObject:Add("CPRCODEIN",hObj:CPRCODEIN) NO-ERROR.
                WHEN "CPRCODEOUT" THEN oJsonObject:Add("CPRCODEOUT",hObj:CPRCODEOUT) NO-ERROR.
                WHEN "CPSTREAM" THEN oJsonObject:Add("CPSTREAM",hObj:CPSTREAM) NO-ERROR.
                WHEN "CPTERM" THEN oJsonObject:Add("CPTERM",hObj:CPTERM) NO-ERROR.
                WHEN "CURRENT-REQUEST-INFO" THEN oJsonObject:Add("CURRENT-REQUEST-INFO",Jsonify(hObj:CURRENT-REQUEST-INFO)) NO-ERROR.
                WHEN "CURRENT-RESPONSE-INFO" THEN oJsonObject:Add("CURRENT-RESPONSE-INFO",Jsonify(hObj:CURRENT-RESPONSE-INFO)) NO-ERROR.
                WHEN "CURRENT-RESULT-ROW" THEN oJsonObject:Add("CURRENT-RESULT-ROW",hObj:CURRENT-RESULT-ROW) NO-ERROR.
                WHEN "CURRENT-WINDOW" THEN oJsonObject:Add("CURRENT-WINDOW",hObj:CURRENT-WINDOW) NO-ERROR.
                WHEN "DATA-ENTRY-RETURN" THEN oJsonObject:Add("DATA-ENTRY-RETURN",hObj:DATA-ENTRY-RETURN) NO-ERROR.
                WHEN "DATE-FORMAT" THEN oJsonObject:Add("DATE-FORMAT",hObj:DATE-FORMAT) NO-ERROR.
                WHEN "DB-REFERENCES" THEN oJsonObject:Add("DB-REFERENCES",hObj:DB-REFERENCES) NO-ERROR.
                WHEN "DEBUG-ALERT" THEN oJsonObject:Add("DEBUG-ALERT",hObj:DEBUG-ALERT) NO-ERROR.
                WHEN "DELETE-RESULT-LIST-ENTRY" THEN oJsonObject:Add("DELETE-RESULT-LIST-ENTRY",hObj:DELETE-RESULT-LIST-ENTRY) NO-ERROR.
                WHEN "DISPLAY-TIMEZONE" THEN oJsonObject:Add("DISPLAY-TIMEZONE",hObj:DISPLAY-TIMEZONE) NO-ERROR.
                WHEN "DISPLAY-TYPE" THEN oJsonObject:Add("DISPLAY-TYPE",hObj:DISPLAY-TYPE) NO-ERROR.
                WHEN "DOTNET-CLR-LOADED" THEN oJsonObject:Add("DOTNET-CLR-LOADED",hObj:DOTNET-CLR-LOADED) NO-ERROR.
                WHEN "DYNAMIC" THEN oJsonObject:Add("DYNAMIC",hObj:DYNAMIC) NO-ERROR.
                WHEN "DATA-SOURCE" THEN oJsonObject:Add("DATA-SOURCE",hObj:DATA-SOURCE) NO-ERROR.
                WHEN "DATA-SOURCE-COMPLETE-MAP" THEN oJsonObject:Add("DATA-SOURCE-COMPLETE-MAP",hObj:DATA-SOURCE-COMPLETE-MAP) NO-ERROR.
                WHEN "DATA-SOURCE-MODIFIED" THEN oJsonObject:Add("DATA-SOURCE-MODIFIED",hObj:DATA-SOURCE-MODIFIED) NO-ERROR.
                WHEN "DATA-SOURCE-ROWID" THEN oJsonObject:Add("DATA-SOURCE-ROWID",hObj:DATA-SOURCE-ROWID) NO-ERROR.
                WHEN "DATA-TYPE" THEN oJsonObject:Add("DATA-TYPE",hObj:DATA-TYPE) NO-ERROR.
                WHEN "DATASET" THEN oJsonObject:Add("DATASET",hObj:DATASET) NO-ERROR.
                WHEN "DBNAME" THEN oJsonObject:Add("DBNAME",hObj:DBNAME) NO-ERROR.
                WHEN "DECIMALS" THEN oJsonObject:Add("DECIMALS",hObj:DECIMALS) NO-ERROR.
                WHEN "DEFAULT-COMMIT" THEN oJsonObject:Add("DEFAULT-COMMIT",hObj:DEFAULT-COMMIT) NO-ERROR.
                WHEN "DEFAULT-STRING" THEN oJsonObject:Add("DEFAULT-STRING",hObj:DEFAULT-STRING) NO-ERROR.
                WHEN "DEFAULT-VALUE" THEN oJsonObject:Add("DEFAULT-VALUE",hObj:DEFAULT-VALUE) NO-ERROR.
                WHEN "DETACH-DATA-SOURCE" THEN oJsonObject:Add("DETACH-DATA-SOURCE",hObj:DETACH-DATA-SOURCE) NO-ERROR.
                WHEN "DISABLE-DUMP-TRIGGERS" THEN oJsonObject:Add("DISABLE-DUMP-TRIGGERS",hObj:DISABLE-DUMP-TRIGGERS) NO-ERROR.
                WHEN "EMPTY-DATASET" THEN oJsonObject:Add("EMPTY-DATASET",hObj:EMPTY-DATASET) NO-ERROR.
                WHEN "ERROR" THEN oJsonObject:Add("ERROR",hObj:ERROR) NO-ERROR.
                WHEN "ERROR-STACK-TRACE" THEN oJsonObject:Add("ERROR-STACK-TRACE",hObj:ERROR-STACK-TRACE) NO-ERROR.
                WHEN "EXECUTION-LOG" THEN oJsonObject:Add("EXECUTION-LOG",hObj:EXECUTION-LOG) NO-ERROR.
                WHEN "EXIT-CODE" THEN oJsonObject:Add("EXIT-CODE",hObj:EXIT-CODE) NO-ERROR.
                WHEN "EXPORT-PRINCIPAL" THEN oJsonObject:Add("EXPORT-PRINCIPAL",hObj:EXPORT-PRINCIPAL) NO-ERROR.
                WHEN "ERROR-STRING" THEN oJsonObject:Add("ERROR-STRING",hObj:ERROR-STRING) NO-ERROR.
                WHEN "EXTENT" THEN oJsonObject:Add("EXTENT",hObj:EXTENT) NO-ERROR.
                WHEN "FIND-CURRENT" THEN oJsonObject:Add("FIND-CURRENT",hObj:FIND-CURRENT) NO-ERROR.
                WHEN "FIND-FIRST" THEN oJsonObject:Add("FIND-FIRST",hObj:FIND-FIRST) NO-ERROR.
                WHEN "FIND-LAST" THEN oJsonObject:Add("FIND-LAST",hObj:FIND-LAST) NO-ERROR.
                WHEN "FIND-UNIQUE" THEN oJsonObject:Add("FIND-UNIQUE",hObj:FIND-UNIQUE) NO-ERROR.
                WHEN "FORMAT" THEN oJsonObject:Add("FORMAT",hObj:FORMAT) NO-ERROR.
                WHEN "FILE-NAME" THEN oJsonObject:Add("FILE-NAME",hObj:FILE-NAME) NO-ERROR.
                WHEN "FILL-MODE" THEN oJsonObject:Add("FILL-MODE",hObj:FILL-MODE) NO-ERROR.
                WHEN "FIRST-ASYNC-REQUEST" THEN oJsonObject:Add("FIRST-ASYNC-REQUEST",hObj:FIRST-ASYNC-REQUEST) NO-ERROR.
                WHEN "FIRST-BUFFER" THEN oJsonObject:Add("FIRST-BUFFER",hObj:FIRST-BUFFER) NO-ERROR.
                WHEN "FIRST-CHILD" THEN oJsonObject:Add("FIRST-CHILD",hObj:FIRST-CHILD) NO-ERROR.
                WHEN "FIRST-DATA-SOURCE" THEN oJsonObject:Add("FIRST-DATA-SOURCE",hObj:FIRST-DATA-SOURCE) NO-ERROR.
                WHEN "FIRST-DATASET" THEN oJsonObject:Add("FIRST-DATASET",hObj:FIRST-DATASET) NO-ERROR.
                WHEN "FIRST-FORM" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "FIRST-OBJECT" THEN DO:
                    IF IncludeObjects THEN oJsonObject:Add("FIRST-OBJECT",Jsonify(hObj:FIRST-OBJECT)) NO-ERROR.
                END.
                WHEN "FIRST-OF" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "FIRST-PROCEDURE" THEN DO:
                    IF IncludeProcs THEN oJsonObject:Add("FIRST-PROCEDURE",Jsonify(hObj:FIRST-PROCEDURE)) NO-ERROR.
                    ELSE oJsonObject:Add("FIRST-PROCEDURE",hObj:FIRST-PROCEDURE) NO-ERROR.
                END.
                WHEN "FIRST-QUERY" THEN oJsonObject:Add("FIRST-QUERY",hObj:FIRST-QUERY) NO-ERROR.
                WHEN "FIRST-SERVER" THEN oJsonObject:Add("FIRST-SERVER",hObj:FIRST-SERVER) NO-ERROR.
                WHEN "FIRST-SERVER-SOCKET" THEN oJsonObject:Add("FIRST-SERVER-SOCKET",hObj:FIRST-SERVER-SOCKET) NO-ERROR.
                WHEN "FIRST-SOCKET" THEN oJsonObject:Add("FIRST-SOCKET",hObj:FIRST-SOCKET) NO-ERROR.
                WHEN "FORWARD-ONLY" THEN oJsonObject:Add("FORWARD-ONLY",hObj:FORWARD-ONLY) NO-ERROR.
                WHEN "FRAME-SPACING" THEN oJsonObject:Add("FRAME-SPACING",hObj:FRAME-SPACING) NO-ERROR.
                WHEN "HANDLE" THEN oJsonObject:Add("HANDLE",hObj:HANDLE) NO-ERROR.
                WHEN "HAS-LOBS" THEN oJsonObject:Add("HAS-LOBS",hObj:HAS-LOBS) NO-ERROR.
                WHEN "HELP" THEN oJsonObject:Add("HELP",hObj:HELP) NO-ERROR.
                WHEN "HEIGHT-CHARS" THEN oJsonObject:Add("HEIGHT-CHARS",hObj:HEIGHT-CHARS) NO-ERROR.
                WHEN "HEIGHT-PIXELS" THEN oJsonObject:Add("HEIGHT-PIXELS",hObj:HEIGHT-PIXELS) NO-ERROR.
                WHEN "ICFPARAMETER" THEN oJsonObject:Add("ICFPARAMETER",hObj:ICFPARAMETER) NO-ERROR.
                WHEN "IMMEDIATE-DISPLAY" THEN oJsonObject:Add("IMMEDIATE-DISPLAY",hObj:IMMEDIATE-DISPLAY) NO-ERROR.
                WHEN "INDEX-INFORMATION" THEN oJsonObject:Add("INDEX-INFORMATION",hObj:INDEX-INFORMATION) NO-ERROR.
                WHEN "INHERIT-BGCOLOR" THEN oJsonObject:Add("INHERIT-BGCOLOR",hObj:INHERIT-BGCOLOR) NO-ERROR.
                WHEN "INHERIT-COLOR-MODE" THEN oJsonObject:Add("INHERIT-COLOR-MODE",hObj:INHERIT-COLOR-MODE) NO-ERROR.
                WHEN "INHERIT-FGCOLOR" THEN oJsonObject:Add("INHERIT-FGCOLOR",hObj:INHERIT-FGCOLOR) NO-ERROR.
                WHEN "INSTANTIATING-PROCEDURE" THEN oJsonObject:Add("INSTANTIATING-PROCEDURE",hObj:INSTANTIATING-PROCEDURE) NO-ERROR.
                WHEN "INTERNAL-ENTRIES" THEN oJsonObject:Add("INTERNAL-ENTRIES",hObj:INTERNAL-ENTRIES) NO-ERROR.
                WHEN "IS-OPEN" THEN oJsonObject:Add("IS-OPEN",hObj:IS-OPEN) NO-ERROR.
                WHEN "INITIAL" THEN oJsonObject:Add("INITIAL",hObj:INITIAL) NO-ERROR.
                WHEN "IS-MULTI-TENANT" THEN oJsonObject:Add("IS-MULTI-TENANT",hObj:IS-MULTI-TENANT) NO-ERROR.
                WHEN "IS-PARTITIONED" THEN oJsonObject:Add("IS-PARTITIONED",hObj:IS-PARTITIONED) NO-ERROR.
                WHEN "KEY" THEN oJsonObject:Add("KEY",hObj:KEY) NO-ERROR.
                WHEN "KEYS" THEN oJsonObject:Add("KEYS",hObj:KEYS) NO-ERROR.
                WHEN "LABEL" THEN oJsonObject:Add("LABEL",hObj:LABEL) NO-ERROR.
                WHEN "LAST-BATCH" THEN oJsonObject:Add("LAST-BATCH",hObj:LAST-BATCH) NO-ERROR.
                WHEN "LITERAL-QUESTION" THEN oJsonObject:Add("LITERAL-QUESTION",hObj:LITERAL-QUESTION) NO-ERROR.
                WHEN "LOCAL-VERSION-INFO" THEN oJsonObject:Add("LOCAL-VERSION-INFO",Jsonify(hObj:LOCAL-VERSION-INFO)) NO-ERROR.
                WHEN "LOCKED" THEN oJsonObject:Add("LOCKED",hObj:LOCKED) NO-ERROR.
                WHEN "LAST-ASYNC-REQUEST" THEN oJsonObject:Add("LAST-ASYNC-REQUEST",hObj:LAST-ASYNC-REQUEST) NO-ERROR.
                WHEN "LAST-CHILD" THEN oJsonObject:Add("LAST-CHILD",hObj:LAST-CHILD) NO-ERROR.
                WHEN "LAST-OBJECT" THEN DO:
                    IF IncludeObjects THEN oJsonObject:Add("LAST-OBJECT",Jsonify(hObj:LAST-OBJECT)) NO-ERROR.
                END.
                WHEN "LAST-PROCEDURE" THEN DO:
                    IF IncludeProcs THEN oJsonObject:Add("LAST-PROCEDURE",Jsonify(hObj:LAST-PROCEDURE)) NO-ERROR.
                    ELSE oJsonObject:Add("LAST-PROCEDURE",hObj:LAST-PROCEDURE) NO-ERROR.
                END.
                WHEN "LAST-SERVER" THEN oJsonObject:Add("LAST-SERVER",hObj:LAST-SERVER) NO-ERROR.
                WHEN "LAST-SERVER-SOCKET" THEN oJsonObject:Add("LAST-SERVER-SOCKET",hObj:LAST-SERVER-SOCKET) NO-ERROR.
                WHEN "LAST-SOCKET" THEN oJsonObject:Add("LAST-SOCKET",hObj:LAST-SOCKET) NO-ERROR.
                WHEN "LIST-PROPERTY-NAMES" THEN oJsonObject:Add("LIST-PROPERTY-NAMES",hObj:LIST-PROPERTY-NAMES) NO-ERROR.
                WHEN "LOCAL-HOST" THEN oJsonObject:Add("LOCAL-HOST",hObj:LOCAL-HOST) NO-ERROR.
                WHEN "LOCAL-PORT" THEN oJsonObject:Add("LOCAL-PORT",hObj:LOCAL-PORT) NO-ERROR.
                WHEN "LOGOUT" THEN oJsonObject:Add("LOGOUT",hObj:LOGOUT) NO-ERROR.
                WHEN "MANDATORY" THEN oJsonObject:Add("MANDATORY",hObj:MANDATORY) NO-ERROR.
                WHEN "MULTITASKING-INTERVAL" THEN oJsonObject:Add("MULTITASKING-INTERVAL",hObj:MULTITASKING-INTERVAL) NO-ERROR.
                WHEN "NAMESPACE-PREFIX" THEN oJsonObject:Add("NAMESPACE-PREFIX",hObj:NAMESPACE-PREFIX) NO-ERROR.
                WHEN "NAMESPACE-URI" THEN oJsonObject:Add("NAMESPACE-URI",hObj:NAMESPACE-URI) NO-ERROR.
                WHEN "NEW" THEN oJsonObject:Add("NEW",hObj:NEW) NO-ERROR.
                WHEN "NEXT-SIBLING" THEN oJsonObject:Add("NEXT-SIBLING",hObj:NEXT-SIBLING) NO-ERROR.
                WHEN "NUM-CHILD-RELATIONS" THEN oJsonObject:Add("NUM-CHILD-RELATIONS",hObj:NUM-CHILD-RELATIONS) NO-ERROR.
                WHEN "NUM-ITERATIONS" THEN oJsonObject:Add("NUM-ITERATIONS",hObj:NUM-ITERATIONS) NO-ERROR.
                WHEN "NUM-REFERENCES" THEN oJsonObject:Add("NUM-REFERENCES",hObj:NUM-REFERENCES) NO-ERROR.
                WHEN "NUM-BUFFERS" THEN oJsonObject:Add("NUM-BUFFERS",hObj:NUM-BUFFERS) NO-ERROR.
                WHEN "NUM-FIELDS" THEN oJsonObject:Add("NUM-FIELDS",hObj:NUM-FIELDS) NO-ERROR.
                WHEN "NUM-RESULTS" THEN oJsonObject:Add("NUM-RESULTS",hObj:NUM-RESULTS) NO-ERROR.
                WHEN "NUMERIC-DECIMAL-POINT" THEN oJsonObject:Add("NUMERIC-DECIMAL-POINT",hObj:NUMERIC-DECIMAL-POINT) NO-ERROR.
                WHEN "NUMERIC-FORMAT" THEN oJsonObject:Add("NUMERIC-FORMAT",hObj:NUMERIC-FORMAT) NO-ERROR.
                WHEN "NUMERIC-SEPARATOR" THEN oJsonObject:Add("NUMERIC-SEPARATOR",hObj:NUMERIC-SEPARATOR) NO-ERROR.
                WHEN "ORIGIN-ROWID" THEN oJsonObject:Add("ORIGIN-ROWID",hObj:ORIGIN-ROWID) NO-ERROR.
                WHEN "OLE-INVOKE-LOCALE" THEN oJsonObject:Add("OLE-INVOKE-LOCALE",hObj:OLE-INVOKE-LOCALE) NO-ERROR.
                WHEN "OLE-NAMES-LOCALE" THEN oJsonObject:Add("OLE-NAMES-LOCALE",hObj:OLE-NAMES-LOCALE) NO-ERROR.
                WHEN "PARAMETER" THEN oJsonObject:Add("PARAMETER",hObj:PARAMETER) NO-ERROR.
                WHEN "PARENT-RELATION" THEN oJsonObject:Add("PARENT-RELATION",hObj:PARENT-RELATION) NO-ERROR.
                WHEN "PERSISTENT" THEN oJsonObject:Add("PERSISTENT",hObj:PERSISTENT) NO-ERROR.
                WHEN "PIXELS-PER-COLUMN" THEN oJsonObject:Add("PIXELS-PER-COLUMN",hObj:PIXELS-PER-COLUMN) NO-ERROR.
                WHEN "PIXELS-PER-ROW" THEN oJsonObject:Add("PIXELS-PER-ROW",hObj:PIXELS-PER-ROW) NO-ERROR.
                WHEN "POSITION" THEN oJsonObject:Add("POSITION",hObj:POSITION) NO-ERROR.
                WHEN "PRIMARY" THEN oJsonObject:Add("PRIMARY",hObj:PRIMARY) NO-ERROR.
                WHEN "PREPARE-STRING" THEN oJsonObject:Add("PREPARE-STRING",hObj:PREPARE-STRING) NO-ERROR.
                WHEN "PRINTER-CONTROL-HANDLE" THEN oJsonObject:Add("PRINTER-CONTROL-HANDLE",hObj:PRINTER-CONTROL-HANDLE) NO-ERROR.
                WHEN "PRINTER-HDC" THEN oJsonObject:Add("PRINTER-HDC",hObj:PRINTER-HDC) NO-ERROR.
                WHEN "PRINTER-NAME" THEN oJsonObject:Add("PRINTER-NAME",hObj:PRINTER-NAME) NO-ERROR.
                WHEN "PRINTER-PORT" THEN oJsonObject:Add("PRINTER-PORT",hObj:PRINTER-PORT) NO-ERROR.
                WHEN "PRIVATE-DATA" THEN oJsonObject:Add("PRIVATE-DATA",hObj:PRIVATE-DATA) NO-ERROR.
                WHEN "PROXY" THEN oJsonObject:Add("PROXY",hObj:PROXY) NO-ERROR.
                WHEN "PROXY-PASSWORD" THEN oJsonObject:Add("PROXY-PASSWORD",hObj:PROXY-PASSWORD) NO-ERROR.
                WHEN "PROXY-USERID" THEN oJsonObject:Add("PROXY-USERID",hObj:PROXY-USERID) NO-ERROR.
                WHEN "PUBLISHED-EVENTS" THEN oJsonObject:Add("PUBLISHED-EVENTS",hObj:PUBLISHED-EVENTS) NO-ERROR.
                WHEN "QUERY" THEN oJsonObject:Add("QUERY",hObj:QUERY) NO-ERROR.
                WHEN "QUERY-OFF-END" THEN oJsonObject:Add("QUERY-OFF-END",hObj:QUERY-OFF-END) NO-ERROR.
                WHEN "QUERY-OPEN" THEN oJsonObject:Add("QUERY-OPEN",hObj:QUERY-OPEN) NO-ERROR.
                WHEN "READ-ONLY" THEN oJsonObject:Add("READ-ONLY",hObj:READ-ONLY) NO-ERROR.
                WHEN "REJECT-CHANGES" THEN oJsonObject:Add("REJECT-CHANGES",hObj:REJECT-CHANGES) NO-ERROR.
                WHEN "REMOTE" THEN oJsonObject:Add("REMOTE",hObj:REMOTE) NO-ERROR.
                WHEN "RECID" THEN oJsonObject:Add("RECID",hObj:RECID) NO-ERROR.
                WHEN "RECORD-LENGTH" THEN oJsonObject:Add("RECORD-LENGTH",hObj:RECORD-LENGTH) NO-ERROR.
                WHEN "REJECTED" THEN oJsonObject:Add("REJECTED",hObj:REJECTED) NO-ERROR.
                WHEN "REMOTE-HOST" THEN oJsonObject:Add("REMOTE-HOST",hObj:REMOTE-HOST) NO-ERROR.
                WHEN "REMOTE-PORT" THEN oJsonObject:Add("REMOTE-PORT",hObj:REMOTE-PORT) NO-ERROR.
                WHEN "ROW-STATE" THEN oJsonObject:Add("ROW-STATE",hObj:ROW-STATE) NO-ERROR.
                WHEN "ROWID" THEN oJsonObject:Add("ROWID",hObj:ROWID) NO-ERROR.
                WHEN "SAVE-ROW-CHANGES" THEN oJsonObject:Add("SAVE-ROW-CHANGES",hObj:SAVE-ROW-CHANGES) NO-ERROR.
                WHEN "SERIALIZE-NAME" THEN oJsonObject:Add("SERIALIZE-NAME",hObj:SERIALIZE-NAME) NO-ERROR.
                WHEN "STRING-VALUE" THEN oJsonObject:Add("STRING-VALUE",hObj:STRING-VALUE) NO-ERROR.
                WHEN "SYNCHRONIZE" THEN oJsonObject:Add("SYNCHRONIZE",hObj:SYNCHRONIZE) NO-ERROR.
                WHEN "SCHEMA-CHANGE" THEN oJsonObject:Add("SCHEMA-CHANGE",hObj:SCHEMA-CHANGE) NO-ERROR.
                WHEN "SENSITIVE" THEN oJsonObject:Add("SENSITIVE",hObj:SENSITIVE) NO-ERROR.
                WHEN "SERIALIZE-HIDDEN" THEN oJsonObject:Add("SERIALIZE-HIDDEN",hObj:SERIALIZE-HIDDEN) NO-ERROR.
                WHEN "SERVER" THEN oJsonObject:Add("SERVER",hObj:SERVER) NO-ERROR.
                WHEN "SERVER-CONNECTION-BOUND" THEN oJsonObject:Add("SERVER-CONNECTION-BOUND",hObj:SERVER-CONNECTION-BOUND) NO-ERROR.
                WHEN "SERVER-CONNECTION-BOUND-REQUEST" THEN oJsonObject:Add("SERVER-CONNECTION-BOUND-REQUEST",hObj:SERVER-CONNECTION-BOUND-REQUEST) NO-ERROR.
                WHEN "SERVER-CONNECTION-CONTEXT" THEN oJsonObject:Add("SERVER-CONNECTION-CONTEXT",hObj:SERVER-CONNECTION-CONTEXT) NO-ERROR.
                WHEN "SERVER-CONNECTION-ID" THEN oJsonObject:Add("SERVER-CONNECTION-ID",hObj:SERVER-CONNECTION-ID) NO-ERROR.
                WHEN "SERVER-OPERATING-MODE" THEN oJsonObject:Add("SERVER-OPERATING-MODE",hObj:SERVER-OPERATING-MODE) NO-ERROR.
                WHEN "SINGLE-RUN" THEN oJsonObject:Add("SINGLE-RUN",hObj:SINGLE-RUN) NO-ERROR.
                WHEN "SINGLETON" THEN oJsonObject:Add("SINGLETON",hObj:SINGLETON) NO-ERROR.
                WHEN "SKIP-DELETED-RECORD" THEN oJsonObject:Add("SKIP-DELETED-RECORD",hObj:SKIP-DELETED-RECORD) NO-ERROR.
                WHEN "SSL-SERVER-NAME" THEN oJsonObject:Add("SSL-SERVER-NAME",hObj:SSL-SERVER-NAME) NO-ERROR.
                WHEN "STARTUP-PARAMETERS" THEN oJsonObject:Add("STARTUP-PARAMETERS",hObj:STARTUP-PARAMETERS) NO-ERROR.
                WHEN "SUPER-PROCEDURES" THEN oJsonObject:Add("SUPER-PROCEDURES",hObj:SUPER-PROCEDURES) NO-ERROR.
                WHEN "SUPPRESS-WARNINGS" THEN oJsonObject:Add("SUPPRESS-WARNINGS",hObj:SUPPRESS-WARNINGS) NO-ERROR.
                WHEN "SUPPRESS-WARNINGS-LIST" THEN oJsonObject:Add("SUPPRESS-WARNINGS-LIST",hObj:SUPPRESS-WARNINGS-LIST) NO-ERROR.
                WHEN "SYSTEM-ALERT-BOXES" THEN oJsonObject:Add("SYSTEM-ALERT-BOXES",hObj:SYSTEM-ALERT-BOXES) NO-ERROR.
                WHEN "TABLE" THEN oJsonObject:Add("TABLE",hObj:TABLE) NO-ERROR.
                WHEN "TABLE-HANDLE" THEN oJsonObject:Add("TABLE-HANDLE",hObj:TABLE-HANDLE) NO-ERROR.
                WHEN "TABLE-NUMBER" THEN oJsonObject:Add("TABLE-NUMBER",hObj:TABLE-NUMBER) NO-ERROR.
                WHEN "TEMP-DIRECTORY" THEN oJsonObject:Add("TEMP-DIRECTORY",hObj:TEMP-DIRECTORY) NO-ERROR.
                WHEN "TENANT-ID" THEN oJsonObject:Add("TENANT-ID",hObj:TENANT-ID) NO-ERROR.
                WHEN "TENANT-NAME" THEN oJsonObject:Add("TENANT-NAME",hObj:TENANT-NAME) NO-ERROR.
                WHEN "THREE-D" THEN oJsonObject:Add("THREE-D",hObj:THREE-D) NO-ERROR.
                WHEN "TIME-SOURCE" THEN oJsonObject:Add("TIME-SOURCE",hObj:TIME-SOURCE) NO-ERROR.
                WHEN "TIMEZONE" THEN oJsonObject:Add("TIMEZONE",hObj:TIMEZONE) NO-ERROR.
                WHEN "TRANSACTION" THEN oJsonObject:Add("TRANSACTION",Jsonify(hObj:TRANSACTION)) NO-ERROR.
                WHEN "TRANS-INIT-PROCEDURE" THEN oJsonObject:Add("TRANS-INIT-PROCEDURE",hObj:TRANS-INIT-PROCEDURE) NO-ERROR.
                WHEN "TOOLTIPS" THEN oJsonObject:Add("TOOLTIPS",hObj:TOOLTIPS) NO-ERROR.
                WHEN "UNIQUE-ID" THEN oJsonObject:Add("UNIQUE-ID",hObj:UNIQUE-ID) NO-ERROR.
                WHEN "V6DISPLAY" THEN oJsonObject:Add("V6DISPLAY",hObj:V6DISPLAY) NO-ERROR.
                WHEN "VALIDATE-EXPRESSION" THEN oJsonObject:Add("VALIDATE-EXPRESSION",hObj:VALIDATE-EXPRESSION) NO-ERROR.
                WHEN "VALIDATE-MESSAGE" THEN oJsonObject:Add("VALIDATE-MESSAGE",hObj:VALIDATE-MESSAGE) NO-ERROR.
                WHEN "VIEW-AS" THEN oJsonObject:Add("VIEW-AS",hObj:VIEW-AS) NO-ERROR.
                WHEN "WIDTH-CHARS" THEN oJsonObject:Add("WIDTH-CHARS",hObj:WIDTH-CHARS) NO-ERROR.
                WHEN "WIDTH-PIXELS" THEN oJsonObject:Add("WIDTH-PIXELS",hObj:WIDTH-PIXELS) NO-ERROR.
                WHEN "WINDOW-SYSTEM" THEN oJsonObject:Add("WINDOW-SYSTEM",hObj:WINDOW-SYSTEM) NO-ERROR.
                WHEN "WORK-AREA-HEIGHT-PIXELS" THEN oJsonObject:Add("WORK-AREA-HEIGHT-PIXELS",hObj:WORK-AREA-HEIGHT-PIXELS) NO-ERROR.
                WHEN "WORK-AREA-WIDTH-PIXELS" THEN oJsonObject:Add("WORK-AREA-WIDTH-PIXELS",hObj:WORK-AREA-WIDTH-PIXELS) NO-ERROR.
                WHEN "WORK-AREA-X" THEN oJsonObject:Add("WORK-AREA-X",hObj:WORK-AREA-X) NO-ERROR.
                WHEN "WORK-AREA-Y" THEN oJsonObject:Add("WORK-AREA-Y",hObj:WORK-AREA-Y) NO-ERROR.
                WHEN "YEAR-OFFSET" THEN oJsonObject:Add("YEAR-OFFSET",hObj:YEAR-OFFSET) NO-ERROR.
                WHEN "XML-DATA-TYPE" THEN oJsonObject:Add("XML-DATA-TYPE",hObj:XML-DATA-TYPE) NO-ERROR.
                WHEN "XML-NODE-NAME" THEN oJsonObject:Add("XML-NODE-NAME",hObj:XML-NODE-NAME) NO-ERROR.
                WHEN "XML-NODE-TYPE" THEN oJsonObject:Add("XML-NODE-TYPE",hObj:XML-NODE-TYPE) NO-ERROR.
            // IGNORE ON PURPOSE
                WHEN "PREV-SIBLING" OR WHEN "NEXT-SIBLING" THEN. // NADA
            // METHODS
                WHEN "ACCEPT-CHANGES" OR
                WHEN "ACCEPT-ROW-CHANGES" OR
                WHEN "ADD-BUFFER" OR                                    
                WHEN "ADD-PARENT-ID-RELATION" OR 
                WHEN "ADD-RELATION" OR 
                WHEN "ADD-SUPER-PROCEDURE" OR 
                WHEN "CONNECT" OR
                WHEN "CONNECTED" OR
                WHEN "COPY-DATASET" OR
                WHEN "CREATE-LIKE" OR
                WHEN "CREATE-RESULT-LIST-ENTRY" OR
                WHEN "DEBUG-SET-TENANT" OR
                WHEN "DISABLE-LOAD-TRIGGERS" OR
                WHEN "DISCONNECT" OR
                WHEN "DUMP-LOGGING-NOW" OR
                WHEN "EXPORT" OR
                WHEN "EMPTY-TEMP-TABLE" OR
                WHEN "FILL" OR
                WHEN "FIND-BY-ROWID" THEN  cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "GET-BUFFER-HANDLE" OR
                WHEN "GET-BYTES-AVAILABLE" OR
                WHEN "GET-CALLBACK-PROC-CONTEXT" OR
                WHEN "GET-CALLBACK-PROC-NAME" OR
                WHEN "GET-CHANGES" OR
                WHEN "GET-CHILD-RELATION" OR
                WHEN "GET-CURRENT" OR
                WHEN "GET-FIRST" OR
                WHEN "GET-ITERATION" OR
                WHEN "GET-LAST" OR
                WHEN "GET-NEXT" OR
                WHEN "GET-PREV" OR
                WHEN "GET-PRINTERS" OR
                WHEN "GET-PROPERTY" OR
                WHEN "GET-RELATION" OR
                WHEN "GET-SIGNATURE" OR
                WHEN "GET-SOCKET-OPTION" OR
                WHEN "GET-TOP-BUFFER" OR
                WHEN "GET-WAIT-STATE" OR            
                WHEN "IMPORT-PRINCIPAL" OR
                WHEN "INITIALIZE" THEN  cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "LOAD-ICON" OR
                WHEN "LAST-FORM" OR
                WHEN "LAST-OF" OR
                WHEN "MARK-NEW" OR
                WHEN "MARK-ROW-STATE" OR
                WHEN "MERGE-CHANGES" OR
                WHEN "MERGE-ROW-CHANGES" OR
                WHEN "QUERY-CLOSE" OR
                WHEN "QUERY-PREPARE" OR
                WHEN "RAW-TRANSFER" OR
                WHEN "READ" OR
                WHEN "READ-JSON" OR
                WHEN "READ-XML" OR
                WHEN "READ-XMLSCHEMA" OR
                WHEN "REJECT-ROW-CHANGES" OR
                WHEN "REMOVE-SUPER-PROCEDURE" OR
                WHEN "REPOSITION-BACKWARDS" OR
                WHEN "REPOSITION-FORWARDS" OR
                WHEN "REPOSITION-PARENT-RELATION" OR
                WHEN "REPOSITION-TO-ROW" OR
                WHEN "REPOSITION-TO-ROWID"  THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "SEAL" OR
                WHEN "SERIALIZE-ROW" OR
                WHEN "SET-BUFFERS" OR
                WHEN "SET-CALLBACK" OR
                WHEN "SET-CALLBACK-PROCEDURE" OR
                WHEN "SET-COMMIT" OR
                WHEN "SET-ROLLBACK" OR
                WHEN "SET-NUMERIC-FORMAT" OR
                WHEN "SET-PROPERTY" OR
                WHEN "SET-READ-RESPONSE-PROCEDURE" OR
                WHEN "SET-SOCKET-OPTION" OR
                WHEN "SET-WAIT-STATE" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr).
                WHEN "VALIDATE-SEAL" OR 
                WHEN "WRITE" OR
                WHEN "WRITE-JSON" OR
                WHEN "WRITE-XML" OR 
                WHEN "WRITE-XMLSCHEMA" THEN cMethodList = SUBSTITUTE("&1,&2",cMethodList,cThisAttr). 
                
                OTHERWISE DO:
                    IF NOT CAN-FIND(FIRST ttUnhandled WHERE ttUnhandled.attrName = cThisAttr)
                        THEN DO:
                        CREATE ttUnhandled.
                        ASSIGN
                            ttUnhandled.attrName = cThisAttr.    
                    END.
                END.
            END CASE.
        END. 
        oJsonObject:Add("METHOD-LIST",TRIM(cMethodList,",")).

        RETURN oJsonObject.
        
        FINALLY:
            
        END FINALLY.
    END METHOD.



END CLASS.