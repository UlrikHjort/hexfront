--  Loading of era definitions and scenario files (plain text).
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Engine.Loader is

   Load_Error : exception;

   --  Directory holding "eras/" and "scenarios/".
   function Data_Dir return String;

   --  Loads a scenario. With Start => False the game is set up but not
   --  started (used when restoring a saved game).
   procedure Load_Scenario (Path : String; Start : Boolean := True);

   --  Load an era's unit types and rules into G (used by the editor).
   procedure Load_Era (Id : String);

   type Scenario_Info is record
      Path        : Unbounded_String;
      Title       : Unbounded_String;
      Era         : Unbounded_String;
      Description : Unbounded_String;
      Category    : Unbounded_String;   --  e.g. Tutorial
      Preview     : Unbounded_String;   --  scenario file to preview
   end record;

   package Info_Vectors is new Ada.Containers.Vectors
     (Positive, Scenario_Info);

   function List_Scenarios return Info_Vectors.Vector;

   --  A light-weight look at a scenario file for the chooser's map
   --  preview; does not touch the running game.
   Preview_Max_Units : constant := 128;
   type Preview_Unit is record
      Col, Row : Integer := 0;
      Side     : Player_Side := 1;
   end record;
   type Preview_Unit_Array is array (1 .. Preview_Max_Units) of Preview_Unit;
   type Glyph_Grid is array (0 .. 59, 0 .. 39) of Character;
   type Owner_Grid is array (0 .. 59, 0 .. 39) of Side_Id;
   type Flag_Grid  is array (0 .. 59, 0 .. 39) of Boolean;
   type Side_Colors is array (Player_Side) of Unbounded_String;

   type Preview_Data is record
      Ok         : Boolean := False;
      Cols, Rows : Natural := 0;
      Glyphs     : Glyph_Grid := (others => (others => '.'));
      Owner      : Owner_Grid := (others => (others => 0));
      Victory    : Flag_Grid  := (others => (others => False));
      Colors     : Side_Colors;          --  "r,g,b"
      Names      : Side_Colors;
      Units      : Preview_Unit_Array;
      Unit_Count : Natural := 0;
      Turns      : Natural := 0;
   end record;

   procedure Read_Preview (Path : String; P : out Preview_Data);

end Engine.Loader;
