-- ***************************************************************************
--                   Hexfront - Engine.Editing
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

--  Scenario editing operations (used by the GUI editor) and writing the
--  current game state back out as a .scn file.
with Ada.Containers.Indefinite_Vectors;
with Engine.Hexes;    use Engine.Hexes;
with Engine.Terrain;  use Engine.Terrain;
with Engine.Units;    use Engine.Units;

package Engine.Editing is

   package Name_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   function List_Eras return Name_Vectors.Vector;

   procedure New_Map (Era_Id : String; Cols, Rows : Positive);

   procedure Paint (H : Hex; T : Terrain_Kind);
   procedure Put_Unit (H : Hex; Side : Player_Side; T : Type_Index);
   procedure Erase (H : Hex);   --  aircraft first, then the ground unit
   procedure Set_Place (H : Hex; Name : String; Owner : Side_Id;
                        Victory : Boolean);

   --  Empty string if the scenario is playable, otherwise the problem.
   function Validate return String;

   procedure Write_Scenario (Path : String);

end Engine.Editing;
