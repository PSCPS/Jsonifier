# Jsonifier
Class that can turn any OpenEdge handle or object reference into JSON for debugging purposes

## How to use:
See the examples in ABLUnit test program test/test_Jsonifier.cls.  

Basically, you define a variable of type JsonObject, then you assign that variable to Jsonifier:Jsonify(yourhandleorobject).
