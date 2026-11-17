with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Engine.Hexes;           use Engine.Hexes;
with Engine.Units;           use Engine.Units;
with Engine.Game;            use Engine.Game;
with Engine.Loader;
with Engine.Campaign;
with Engine.Text_Util;       use Engine.Text_Util;

package body Engine.Save is

   Magic : constant String := "hexfront-save 1";

   function Save_Dir return String is
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME") else ".");
      Dir  : constant String := Home & "/.hexfront/saves";
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
      return Dir;
   exception
      when others =>
         return ".";
   end Save_Dir;

   function B (X : Boolean) return String is (if X then "1" else "0");

   procedure Save_Game (Path : String) is
      F : File_Type;
   begin
      if not G.Loaded then
         raise Save_Error with "no game in progress";
      end if;
      Create (F, Out_File, Path);
      Put_Line (F, Magic);
      Put_Line (F, "scenario " & To_String (G.Scenario_Path));
      Put_Line (F, "state turn=" & Image (G.Turn)
                & " current=" & Image (Integer (G.Current))
                & " winner=" & Image (Integer (G.Winner))
                & " fog=" & B (G.Fog) & " fair=" & B (G.Fair_AI));
      for S in Player_Side loop
         Put_Line (F, "side n=" & Image (Integer (S))
                   & " control="
                   & (if G.Sides (S).Control = Human then "human" else "ai")
                   & " prestige=" & Image (G.Sides (S).Prestige));
      end loop;
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Owner /= 0 then
               Put_Line (F, "owner at=" & Image ((C, R))
                         & " side=" & Image (Integer (G.Cells (C, R).Owner)));
            end if;
         end loop;
      end loop;
      for I in G.Hints.First_Index .. G.Hints.Last_Index loop
         if G.Hints (I).Shown then
            Put_Line (F, "hint_shown n=" & Image (I));
         end if;
      end loop;
      for U of G.Units loop
         if U.Alive then
            Put_Line
              (F, "unit type=" & To_String (G.Types (U.Kind).Id)
               & " side=" & Image (Integer (U.Side))
               & " at=" & Image (U.Pos)
               & " str=" & Image (U.Strength)
               & " ammo=" & Image (U.Ammo) & " fuel=" & Image (U.Fuel)
               & " exp=" & Image (U.Experience)
               & " ent=" & Image (U.Entrench)
               & " sup=" & Image (U.Suppressed)
               & " moves=" & Image (U.Moves_Left)
               & " moved=" & B (U.Has_Moved)
               & " attacked=" & B (U.Has_Attacked)
               & " core=" & B (U.Core));
         end if;
      end loop;
      Engine.Campaign.Write_State (F);
      Close (F);
   exception
      when Name_Error | Use_Error =>
         raise Save_Error with "cannot write " & Path;
   end Save_Game;

   function Parse_Hex (S : String) return Hex is
   begin
      for I in S'Range loop
         if S (I) = ',' then
            return (Integer'Value (S (S'First .. I - 1)),
                    Integer'Value (S (I + 1 .. S'Last)));
         end if;
      end loop;
      raise Save_Error with "bad coordinate " & S;
   end Parse_Hex;

   procedure Load_Game (Path : String) is
      F : File_Type;
   begin
      Open (F, In_File, Path);
      if End_Of_File (F) or else Get_Line (F) /= Magic then
         Close (F);
         raise Save_Error with Path & " is not a Hexfront save";
      end if;
      Engine.Campaign.Stop;
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            KW   : constant String := Keyword (Line);
         begin
            if KW = "scenario" then
               Engine.Loader.Load_Scenario (Rest (Line), Start => False);
               --  Ownership and units come from the save instead.
               G.Units.Clear;
               for C in 0 .. G.Cols - 1 loop
                  for R in 0 .. G.Rows - 1 loop
                     G.Cells (C, R).Owner := 0;
                  end loop;
               end loop;
            elsif KW = "state" then
               G.Turn    := Int (Line, "turn", 1);
               G.Current := Player_Side (Int (Line, "current", 1));
               G.Winner  := Side_Id (Int (Line, "winner", 0));
               G.Fog     := Int (Line, "fog", 1) = 1;
               G.Fair_AI := Int (Line, "fair", 1) = 1;
            elsif KW = "side" then
               declare
                  S : constant Player_Side := Player_Side (Int (Line, "n", 1));
               begin
                  G.Sides (S).Control :=
                    (if Value (Line, "control") = "ai" then Computer
                     else Human);
                  G.Sides (S).Prestige := Int (Line, "prestige", 0);
               end;
            elsif KW = "owner" then
               declare
                  H : constant Hex := Parse_Hex (Value (Line, "at"));
               begin
                  G.Cells (H.Col, H.Row).Owner :=
                    Side_Id (Int (Line, "side", 0));
               end;
            elsif KW = "hint_shown" then
               declare
                  N : constant Integer := Int (Line, "n", 0);
               begin
                  if N in G.Hints.First_Index .. G.Hints.Last_Index then
                     G.Hints (N).Shown := True;
                  end if;
               end;
            elsif KW = "unit" then
               declare
                  U : Unit;
                  T : constant Natural := Find_Type (Value (Line, "type"));
               begin
                  if T = 0 then
                     raise Save_Error with "unknown unit type in save";
                  end if;
                  U.Kind := T;
                  U.Side := Player_Side (Int (Line, "side", 1));
                  U.Pos  := Parse_Hex (Value (Line, "at"));
                  U.Strength   := Int (Line, "str", 10);
                  U.Ammo       := Int (Line, "ammo", 0);
                  U.Fuel       := Int (Line, "fuel", 0);
                  U.Experience := Int (Line, "exp", 0);
                  U.Entrench   := Int (Line, "ent", 0);
                  U.Suppressed := Int (Line, "sup", 0);
                  U.Moves_Left := Int (Line, "moves", 0);
                  U.Has_Moved    := Int (Line, "moved", 0) = 1;
                  U.Has_Attacked := Int (Line, "attacked", 0) = 1;
                  U.Core         := Int (Line, "core", 0) = 1;
                  G.Units.Append (U);
               end;
            else
               Engine.Campaign.Read_State_Line (Line);
            end if;
         end;
      end loop;
      Close (F);
      Place_Occupants;
      Update_Vision;
      G.Loaded := True;
      Messages.Clear;
      Log ("Game loaded: " & To_String (G.Title) & ", turn"
           & Positive'Image (G.Turn));
   exception
      when Name_Error | Use_Error =>
         raise Save_Error with "cannot open " & Path;
   end Load_Game;

end Engine.Save;
