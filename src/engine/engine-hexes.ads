--  Hex grid geometry. Flat-topped hexes in "odd-q" offset layout:
--  odd columns are shifted half a hex down.
package Engine.Hexes is
   pragma Pure;

   type Hex is record
      Col : Integer := -1;
      Row : Integer := -1;
   end record;

   No_Hex : constant Hex := (-1, -1);

   type Direction is range 0 .. 5;

   function Neighbor (H : Hex; D : Direction) return Hex;
   function Distance (A, B : Hex) return Natural;
   function Image (H : Hex) return String;
end Engine.Hexes;
