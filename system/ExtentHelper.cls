 
 /*------------------------------------------------------------------------
    File        : ExtentHelper
    Purpose     : Due to a shortcoming in the ABL, there's no built-in way to dynamically
                  determine the extent of a variable extent property of an object. So
                  this uses trial-and-error referencing extents until it finds the highest
                  number.
    Syntax      : 
    Description : 
    Author(s)   : S.E. Southwell
    Created     : Thu Dec 26 10:33:25 CST 2024
    ABLUnit     : test_ExtentHelper
    Notes       : 
  ----------------------------------------------------------------------*/


BLOCK-LEVEL ON ERROR UNDO, THROW.

USING Progress.Lang.Object FROM PROPATH.

CLASS system.ExtentHelper: 

    /*------------------------------------------------------------------------------
     Purpose: Stupid way of getting the extent value of an unknown property of an object
     Notes:   For performance, start at 1, then 2, 4, 8, 16, 32 and so on until you hit one that doesn't work,
                then binary search from the last working number up to the number that didn't work.
              Benchmark:  For 1000 random extents between 1 and 1074, it was about 300 ms, or .3 ms per search
    ------------------------------------------------------------------------------*/

    METHOD PUBLIC STATIC INTEGER GetExtent(
        INPUT oObj AS Object, 
        INPUT propname AS CHARACTER):
        DEFINE VARIABLE iExtentCount AS INTEGER INIT 1 NO-UNDO.
        DEFINE VARIABLE iLowerWorking AS INTEGER NO-UNDO.
        DEFINE VARIABLE iUpperNonworking AS INTEGER NO-UNDO.
        
        // Find an initial magnitude of size: 1,2,4,8,16,32 and so on
        REPEATBLOCK:
        REPEAT:
            DYNAMIC-PROPERTY(oObj,propname,iExtentCount) NO-ERROR.
            IF ERROR-STATUS:ERROR THEN DO:
                iUpperNonworking = iExtentCount.
                LEAVE REPEATBLOCK.
            END.
            iLowerWorking = iExtentCount.
            iExtentCount = iExtentCount * 2.
        END.

        IF iUpperNonworking = 1 THEN RETURN ?.  // Extent is not fixed.
        
        // Binary search between bounds
        REPEAT:
           IF iLowerWorking = iUpperNonWorking - 1 THEN RETURN iLowerWorking.
           iExtentCount = iLowerWorking + INTEGER((iUpperNonWorking - iLowerWorking) / 2). 
            DYNAMIC-PROPERTY(oObj,propname,iExtentCount) NO-ERROR.
            IF ERROR-STATUS:ERROR THEN DO:
                iUpperNonworking = iExtentCount.
                NEXT.
            END.
            iLowerWorking = iExtentCount.
        END.
    END METHOD.

END CLASS.