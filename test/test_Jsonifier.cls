 
 /*------------------------------------------------------------------------
    File        : test_Jsonifier
    Purpose     : 
    Syntax      : 
    Description : 
    Author(s)   : S.E. Southwell
    Created     : Mon Dec 23 11:00:11 CST 2024
    Notes       : 
  ----------------------------------------------------------------------*/


BLOCK-LEVEL ON ERROR UNDO, THROW.

USING OpenEdge.Core.Assert FROM PROPATH.
USING OpenEdge.Web.WebRequest FROM PROPATH.
USING Progress.Json.ObjectModel.JsonObject FROM PROPATH.
USING test.TestClass FROM PROPATH.
USING system.Jsonifier FROM PROPATH.

&SCOPED-DEFINE SEAL-KEY "2893DomainYankeeCorkZebraBonkers"

CLASS test.test_Jsonifier:
    
    DEFINE PROTECTED TEMP-TABLE ttTestTempTable NO-UNDO
        FIELD Id AS INT64
        FIELD ValueText AS CHARACTER
        INDEX Id IS PRIMARY UNIQUE Id.
        
    DEFINE PROTECTED DATASET dsTestDataset FOR ttTestTempTable.
    
    @Test.
    METHOD PUBLIC VOID test_object1():
        DEFINE VARIABLE oObj AS Progress.Lang.Object NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        oJsonOut = Jsonifier:Jsonify(oObj).
        oJsonOut:WriteFile("testoutput/test_object1.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TypeName"),"Has type").
        Assert:Equals("invalidObject", oJsonOut:GetCharacter("TypeName")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_object2():
        DEFINE VARIABLE oObj AS JsonObject NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        oObj = NEW JsonObject().
        oObj:Add("Foo", 1).
        oObj:Add("Bar", FALSE).
        oObj:Add("Baz", "Aww yeah!").
        oJsonOut = Jsonifier:Jsonify(oObj).
        oJsonOut:WriteFile("testoutput/test_object2.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TypeName"),"Has type").
        Assert:Equals("Progress.Json.ObjectModel.JsonObject", oJsonOut:GetCharacter("TypeName")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_object3():
        DEFINE VARIABLE oObj AS WebRequest NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        oObj = NEW WebRequest().
        oJsonOut = Jsonifier:Jsonify(oObj).
        oJsonOut:WriteFile("testoutput/test_object3.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TypeName"),"Has type").
        Assert:Equals("OpenEdge.Web.WebRequest", oJsonOut:GetCharacter("TypeName")).
        FINALLY:
            DELETE OBJECT oObj.
            DELETE OBJECT oJsonOut.
        END FINALLY.
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_object4():
        DEFINE VARIABLE oObj AS TestClass NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        oObj = NEW TestClass().
        Jsonifier:DetailLevel = 1.
        oJsonOut = Jsonifier:Jsonify(oObj).
        oJsonOut:WriteFile("testoutput/test_object4.json",TRUE).
        
        Assert:Equals("test.TestClass", oJsonOut:GetCharacter("TypeName")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_invalid():
        DEFINE VARIABLE hInvalid AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        Jsonifier:DetailLevel = 3.
        oJsonOut = Jsonifier:Jsonify(hInvalid).
        oJsonOut:WriteFile("testoutput/test_handle_invalid.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("invalidHandle", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_cp():
        DEFINE VARIABLE hCP AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        Jsonifier:DetailLevel = 3.
        CREATE CLIENT-PRINCIPAL hCP.
        hCP:INITIALIZE("ssouthwe@progress.com","1000001",NOW + 100000).
        hCP:SET-PROPERTY ("FOO","This is a foo").
        hCP:SET-PROPERTY("BAR","This is a bar").
        hCP:ROLES = "psc_user,psc_admin".
        hCP:SEAL ({&SEAL-KEY}).
        oJsonOut = Jsonifier:Jsonify(hCP).
        oJsonOut:WriteFile("testoutput/test_handle_cp.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("CLIENT-PRINCIPAL", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_dataset():
        DEFINE VARIABLE hDS AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        Jsonifier:DetailLevel = 3.
        hDS = DATASET dsTestDataset:HANDLE.
        CREATE ttTestTempTable.
        ASSIGN
            ttTestTempTable.Id = 1
            ttTestTempTable.ValueText = "This is a test".
        oJsonOut = Jsonifier:Jsonify(hDS).
        oJsonOut:WriteFile("testoutput/test_handle_dataset.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("DATASET", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_query():
        DEFINE VARIABLE hObj AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.

        CREATE QUERY hObj.        
        hObj:ADD-BUFFER(BUFFER ttTestTempTable:HANDLE).
        hObj:QUERY-PREPARE("FOR EACH ttTestTempTable").
        hObj:QUERY-OPEN().
        
        oJsonOut = Jsonifier:Jsonify(hObj).
        oJsonOut:WriteFile("testoutput/test_handle_query.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("QUERY", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_prochdl():
        DEFINE VARIABLE hObj AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.

        RUN test/testprochdl.p PERSISTENT SET hObj.
        SESSION:ADD-SUPER-PROCEDURE (hObj).
        oJsonOut = Jsonifier:Jsonify(hObj).
        oJsonOut:WriteFile("testoutput/test_handle_proc.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("PROCEDURE", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_session():
        DEFINE VARIABLE hObj AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.

        hObj = SESSION:HANDLE.  
        Jsonifier:IncludeObjects = FALSE.
        Jsonifier:IncludeProcs = TRUE.     
        oJsonOut = Jsonifier:Jsonify(hObj).
        oJsonOut:WriteFile("testoutput/test_handle_session.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("PSEUDO-WIDGET", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.

    @Test.
    METHOD PUBLIC VOID test_handle_socketobj():
        DEFINE VARIABLE hObj AS HANDLE NO-UNDO.
        DEFINE VARIABLE oJsonOut AS JsonObject NO-UNDO.
        
        CREATE SOCKET hObj.    
        oJsonOut = Jsonifier:Jsonify(hObj).
        oJsonOut:WriteFile("testoutput/test_handle_socket.json",TRUE).
        
        Assert:IsTrue(oJsonOut:Has("TYPE"),"Has type").
        Assert:Equals("SOCKET", oJsonOut:GetCharacter("TYPE")).
        
    END METHOD.


    @Test.
    METHOD PUBLIC VOID test_unhandled():
        Jsonifier:DumpUnhandled().
    END METHOD.

END CLASS.