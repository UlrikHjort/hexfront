--  Tiny helpers for the "keyword key=value key=value ..." line format.
package Engine.Text_Util is
   function Keyword (Line : String) return String;       --  lower-cased
   function Rest (Line : String) return String;          --  after keyword
   function Value (Line, Key : String; Default : String := "") return String;
   function Int (Line, Key : String; Default : Integer := 0) return Integer;
   function Has (Line, Key : String) return Boolean;     --  bare or key=
   function Image (N : Integer) return String;           --  no blank
end Engine.Text_Util;
