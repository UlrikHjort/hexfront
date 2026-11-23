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

with Ada.Text_IO;              use Ada.Text_IO;
with Ada.Directories;          use Ada.Directories;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;  use Ada.Characters.Handling;
with Engine.Game;              use Engine.Game;
with Engine.Loader;
with Engine.Text_Util;         use Engine.Text_Util;

package body Engine.Editing is

   function List_Eras return Name_Vectors.Vector is
      Result : Name_Vectors.Vector;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
      Dir    : constant String := Engine.Loader.Data_Dir & "/eras";
   begin
      if Exists (Dir) then
         Start_Search (Search, Dir, "*.era");
         while More_Entries (Search) loop
            Get_Next_Entry (Search, Item);
            Result.Append (Base_Name (Simple_Name (Item)));
         end loop;
         End_Search (Search);
      end if;
      return Result;
   end List_Eras;

   procedure New_Map (Era_Id : String; Cols, Rows : Positive) is
   begin
      Reset;
      Engine.Loader.Load_Era (Era_Id);
      G.Cols := Natural'Min (Cols, Max_Cols);
      G.Rows := Natural'Min (Rows, Max_Rows);
      G.Title := To_Unbounded_String ("New scenario");
      G.Description := To_Unbounded_String ("Describe the situation here.");
      G.Max_Turns := 12;
      G.Sides (1) := (Name => To_Unbounded_String ("Blue Force"),
                      Color => (0.24, 0.39, 0.70), Control => Human,
                      Prestige => 150, Income => 20, Buy_List => <>);
      G.Sides (2) := (Name => To_Unbounded_String ("Red Force"),
                      Color => (0.67, 0.24, 0.20), Control => Computer,
                      Prestige => 100, Income => 15, Buy_List => <>);
      G.Loaded := True;
   end New_Map;

   procedure Paint (H : Hex; T : Terrain_Kind) is
   begin
      if not In_Map (H) then
         return;
      end if;
      G.Cells (H.Col, H.Row).Terrain := T;
      --  Ground units cannot stand in water.
      if T = Water and then Unit_At (H) /= No_Unit then
         Remove_Unit (Unit_At (H));
      end if;
      if not Is_Capturable (T) and then not G.Cells (H.Col, H.Row).Victory
      then
         G.Cells (H.Col, H.Row).Owner := 0;
      end if;
   end Paint;

   procedure Put_Unit (H : Hex; Side : Player_Side; T : Type_Index) is
      U : Unit;
      Flying : constant Boolean := Is_Air (G.Types (T));
   begin
      if not In_Map (H) then
         return;
      end if;
      if not Flying and then Terrain_At (H) = Water then
         return;
      end if;
      declare
         Old : constant Natural := (if Flying then Air_At (H)
                                    else Unit_At (H));
      begin
         if Old /= No_Unit then
            Remove_Unit (Old);
         end if;
      end;
      U.Kind := T;
      U.Side := Side;
      U.Pos  := H;
      U.Ammo := G.Types (T).Max_Ammo;
      U.Fuel := G.Types (T).Max_Fuel;
      Add_Unit (U);
   end Put_Unit;

   procedure Erase (H : Hex) is
   begin
      if Air_At (H) /= No_Unit then
         Remove_Unit (Air_At (H));
      elsif Unit_At (H) /= No_Unit then
         Remove_Unit (Unit_At (H));
      end if;
   end Erase;

   procedure Set_Place (H : Hex; Name : String; Owner : Side_Id;
                        Victory : Boolean) is
   begin
      if In_Map (H) then
         G.Cells (H.Col, H.Row).Name    := To_Unbounded_String (Name);
         G.Cells (H.Col, H.Row).Owner   := Owner;
         G.Cells (H.Col, H.Row).Victory := Victory;
      end if;
   end Set_Place;

   function Validate return String is
      Count : array (Player_Side) of Natural := (0, 0);
   begin
      if G.Cols = 0 then
         return "There is no map.";
      end if;
      for U of G.Units loop
         if U.Alive then
            Count (U.Side) := Count (U.Side) + 1;
         end if;
      end loop;
      for S in Player_Side loop
         if Count (S) = 0 then
            return "Side" & S'Image & " has no units.";
         end if;
      end loop;
      if Victory_Hexes_Total = 0 then
         return "There are no objectives (victory hexes).";
      end if;
      if Victory_Hexes_Owned (G.Attacker) = Victory_Hexes_Total then
         return "The attacker already holds every objective.";
      end if;
      return "";
   end Validate;

   ---------------------
   -- Write_Scenario --
   ---------------------

   function Token (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C = ' ' then
            C := '_';
         end if;
      end loop;
      return R;
   end Token;

   function C255 (F : Float) return String is
     (Image (Integer (Float'Max (0.0, Float'Min (1.0, F)) * 255.0)));

   Glyphs : constant array (Terrain_Kind) of Character :=
     (Clear => '.', Road => '=', Forest => 'f', Hills => 'h',
      Mountain => 'M', River => '~', Swamp => 's', Town => 't', City => 'C',
      Fortress => 'F', Water => 'w', Trench => '#', Airfield => 'A');

   procedure Write_Scenario (Path : String) is
      F : File_Type;

      --  Wrap long text over several "<keyword> ..." lines.
      procedure Wrapped (Keyword, Text : String) is
         Rest : Unbounded_String := To_Unbounded_String (Text);
      begin
         while Length (Rest) > 0 loop
            declare
               S   : constant String := To_String (Rest);
               Cut : Natural := S'Last;
            begin
               if S'Length > 72 then
                  Cut := Ada.Strings.Fixed.Index
                    (S (S'First .. S'First + 72), " ", Ada.Strings.Backward);
                  if Cut = 0 then
                     Cut := S'First + 72;
                  end if;
               end if;
               Put_Line (F, Keyword & " "
                         & Ada.Strings.Fixed.Trim (S (S'First .. Cut),
                                                   Ada.Strings.Both));
               Rest := To_Unbounded_String (S (Cut + 1 .. S'Last));
               Rest := Ada.Strings.Unbounded.Trim (Rest, Ada.Strings.Left);
            end;
         end loop;
      end Wrapped;
   begin
      Create (F, Out_File, Path);
      Put_Line (F, "# Hexfront scenario (written by the scenario editor)");
      Put_Line (F, "title " & To_String (G.Title));
      if Length (G.Category) > 0 then
         Put_Line (F, "category " & To_String (G.Category));
      end if;
      Wrapped ("description", To_String (G.Description));
      Put_Line (F, "era " & To_String (G.Era.Id));
      Put_Line (F, "turns" & G.Max_Turns'Image);
      Put_Line (F, "attacker" & G.Attacker'Image);
      Put_Line (F, "first" & G.First'Image);
      Put_Line (F, "fog " & (if G.Fog then "on" else "off"));
      if G.Climate /= Always_Fair then
         Put_Line (F, "climate " & Climate_Name (G.Climate));
      end if;
      for W of G.Weather_Plan loop
         Put_Line (F, "weather turn=" & Image (W.Turn) & " "
                   & (if W.Kind = Mist then "fog"
                      else To_Lower (Weather_Name (W.Kind))));
      end loop;
      for S in Player_Side loop
         if G.Supply_Edge (S) /= Auto then
            Put_Line (F, "supply side=" & Image (Integer (S))
                      & " edge=" & Edge_Name (G.Supply_Edge (S)));
         end if;
      end loop;
      for S in Player_Side loop
         declare
            I : constant Side_Info := G.Sides (S);
         begin
            Put_Line (F, "side" & S'Image
                      & " name=" & Token (To_String (I.Name))
                      & " color=" & C255 (I.Color.R) & "," & C255 (I.Color.G)
                      & "," & C255 (I.Color.B)
                      & " control="
                      & (if I.Control = Human then "human" else "ai")
                      & " prestige=" & Image (I.Prestige)
                      & " income=" & Image (I.Income));
            declare
               B : constant String := To_String (I.Buy_List);
            begin
               if B = "none" then
                  Put_Line (F, "buy side=" & Image (Integer (S))
                            & " types=none");
               elsif B'Length > 2 then
                  Put_Line (F, "buy side=" & Image (Integer (S)) & " types="
                            & B (B'First + 1 .. B'Last - 1));
               end if;
            end;
         end;
      end loop;

      Put_Line (F, "map" & G.Cols'Image & G.Rows'Image);
      for R in 0 .. G.Rows - 1 loop
         declare
            Line : String (1 .. 2 * G.Cols - 1) := (others => ' ');
         begin
            for C in 0 .. G.Cols - 1 loop
               Line (2 * C + 1) := Glyphs (G.Cells (C, R).Terrain);
            end loop;
            Put_Line (F, Line);
         end;
      end loop;

      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            declare
               Ce : constant Cell := G.Cells (C, R);
            begin
               if Length (Ce.Name) > 0 or else Ce.Victory
                 or else (Is_Capturable (Ce.Terrain) and then Ce.Owner /= 0)
               then
                  Put_Line (F, "place at=" & Image ((C, R))
                            & (if Length (Ce.Name) > 0
                               then " name=" & Token (To_String (Ce.Name))
                               else "")
                            & " owner=" & Image (Integer (Ce.Owner))
                            & (if Ce.Victory then " victory" else ""));
               end if;
            end;
         end loop;
      end loop;

      for H of G.Hints loop
         declare
            T     : constant String := To_String (H.Text);
            Start : Natural := T'First;
            First : Boolean := True;
         begin
            for I in T'First .. T'Last + 1 loop
               if I > T'Last or else T (I) = ASCII.LF then
                  if First then
                     Put_Line (F, "hint "
                               & (if H.Turn > 0 then "turn=" & Image (H.Turn)
                                  else "event=" & To_String (H.Event))
                               & " " & T (Start .. I - 1));
                     First := False;
                  else
                     Put_Line (F, "more " & T (Start .. I - 1));
                  end if;
                  Start := I + 1;
               end if;
            end loop;
         end;
      end loop;

      for R of G.Reinforcements loop
         Put_Line (F, "reinforce turn=" & Image (R.Turn)
                   & " side=" & Image (Integer (R.Side))
                   & " type=" & To_String (G.Types (R.Kind).Id)
                   & " at=" & Image (R.Pos)
                   & (if R.Core then " core" else ""));
      end loop;
      for U of G.Units loop
         if U.Alive then
            Put_Line (F, "unit side=" & Image (Integer (U.Side))
                      & " type=" & To_String (G.Types (U.Kind).Id)
                      & " at=" & Image (U.Pos)
                      & (if U.Strength /= Max_Strength
                         then " str=" & Image (U.Strength) else "")
                      & (if U.Experience > 0
                         then " exp=" & Image (U.Experience) else "")
                      & (if U.Entrench > 0
                         then " entrench=" & Image (U.Entrench) else "")
                      & (if U.Core then " core" else ""));
         end if;
      end loop;
      Close (F);
   end Write_Scenario;

end Engine.Editing;
