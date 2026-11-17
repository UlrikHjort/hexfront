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
