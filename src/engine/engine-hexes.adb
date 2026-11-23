-- ***************************************************************************
--                    Hexfront - Engine.Hexes
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

package body Engine.Hexes is

   type Offset is record
      DC, DR : Integer;
   end record;
   type Offset_Table is array (Direction) of Offset;

   Even_Col : constant Offset_Table :=
     ((1, -1), (1, 0), (0, 1), (-1, 0), (-1, -1), (0, -1));
   Odd_Col  : constant Offset_Table :=
     ((1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (0, -1));

   function Neighbor (H : Hex; D : Direction) return Hex is
      O : constant Offset :=
        (if H.Col mod 2 = 0 then Even_Col (D) else Odd_Col (D));
   begin
      return (H.Col + O.DC, H.Row + O.DR);
   end Neighbor;

   function Distance (A, B : Hex) return Natural is
      --  Convert to cube coordinates.
      AX : constant Integer := A.Col;
      AZ : constant Integer := A.Row - (A.Col - (A.Col mod 2)) / 2;
      AY : constant Integer := -AX - AZ;
      BX : constant Integer := B.Col;
      BZ : constant Integer := B.Row - (B.Col - (B.Col mod 2)) / 2;
      BY : constant Integer := -BX - BZ;
   begin
      return Integer'Max (abs (AX - BX),
                          Integer'Max (abs (AY - BY), abs (AZ - BZ)));
   end Distance;

   function Image (H : Hex) return String is
      C : constant String := Integer'Image (H.Col);
      R : constant String := Integer'Image (H.Row);
   begin
      return C (C'First + 1 .. C'Last) & "," & R (R'First + 1 .. R'Last);
   end Image;

end Engine.Hexes;
