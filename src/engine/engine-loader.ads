-- ***************************************************************************
--                   Hexfront - Engine.Loader
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

--  Loading of era definitions and scenario files (plain text).
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Engine.Loader is

   Load_Error : exception;

   --  Directory holding "eras/" and "scenarios/": $HEXFRONT_DATA, ./data,
   --  data/ next to or above the program, or <prefix>/share/hexfront.
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
