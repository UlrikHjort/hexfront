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

with Ada.Text_IO;              use Ada.Text_IO;
with Ada.Directories;          use Ada.Directories;
with Ada.Command_Line;
with Ada.Environment_Variables;
with GNAT.OS_Lib;            use type GNAT.OS_Lib.String_Access;
with Ada.Strings.Fixed;        use Ada.Strings.Fixed;
with Ada.Characters.Handling;  use Ada.Characters.Handling;
with Ada.Containers.Generic_Array_Sort;
with Engine.Hexes;             use Engine.Hexes;
with Engine.Terrain;           use Engine.Terrain;
with Engine.Units;             use Engine.Units;
with Engine.Game;              use Engine.Game;

package body Engine.Loader is

   --------------
   -- Data_Dir --
   --------------

   function Data_Dir return String is

      --  Directory of the running program, also when started via PATH.
      function Exe_Dir return String is
         Cmd  : constant String := Ada.Command_Line.Command_Name;
         Path : GNAT.OS_Lib.String_Access :=
           GNAT.OS_Lib.Locate_Exec_On_Path (Cmd);
      begin
         if Path = null then
            return Containing_Directory (Cmd);
         end if;
         declare
            Dir : constant String := Containing_Directory (Path.all);
         begin
            GNAT.OS_Lib.Free (Path);
            return Dir;
         end;
      exception
         when others =>
            return ".";
      end Exe_Dir;

      function Ok (D : String) return Boolean is
        (D'Length > 0 and then Exists (D & "/scenarios"));
   begin
      if Ada.Environment_Variables.Exists ("HEXFRONT_DATA")
        and then Ok (Ada.Environment_Variables.Value ("HEXFRONT_DATA"))
      then
         return Ada.Environment_Variables.Value ("HEXFRONT_DATA");
      elsif Ok ("data") then
         return "data";
      end if;
      declare
         E : constant String := Exe_Dir;
      begin
         if Ok (E & "/../data") then
            return E & "/../data";
         elsif Ok (E & "/data") then
            return E & "/data";
         elsif Ok (E & "/../share/hexfront") then
            return E & "/../share/hexfront";
         end if;
      end;
      return "data";
   exception
      when others =>
         return "data";
   end Data_Dir;

   ---------------
   -- Tokenizer --
   ---------------

   type Token_Array is array (1 .. 64) of Unbounded_String;

   type Line_Info is record
      Keyword : Unbounded_String;
      Rest    : Unbounded_String;   --  everything after the keyword
      Tokens  : Token_Array;
      Count   : Natural := 0;
   end record;

   function Split (Line : String) return Line_Info is
      L : Line_Info;
      I : Natural := Line'First;
      Start : Natural;
      First : Boolean := True;
   begin
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) in ' ' | ASCII.HT loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         Start := I;
         while I <= Line'Last and then Line (I) not in ' ' | ASCII.HT loop
            I := I + 1;
         end loop;
         if First then
            L.Keyword :=
              To_Unbounded_String (To_Lower (Line (Start .. I - 1)));
            L.Rest := To_Unbounded_String (Trim (Line (I .. Line'Last),
                                           Ada.Strings.Both));
            First := False;
         elsif L.Count < Token_Array'Last then
            L.Count := L.Count + 1;
            L.Tokens (L.Count) := To_Unbounded_String (Line (Start .. I - 1));
         end if;
      end loop;
      return L;
   end Split;

   function Has_Key (L : Line_Info; Key : String) return Boolean is
   begin
      for I in 1 .. L.Count loop
         declare
            T : constant String := To_String (L.Tokens (I));
            P : constant Natural := Index (T, "=");
         begin
            if (P = 0 and then To_Lower (T) = Key)
              or else (P > 0 and then To_Lower (T (T'First .. P - 1)) = Key)
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has_Key;

   function Value (L : Line_Info; Key : String; Default : String := "")
                   return String is
   begin
      for I in 1 .. L.Count loop
         declare
            T : constant String := To_String (L.Tokens (I));
            P : constant Natural := Index (T, "=");
         begin
            if P > 0 and then To_Lower (T (T'First .. P - 1)) = Key then
               return T (P + 1 .. T'Last);
            end if;
         end;
      end loop;
      return Default;
   end Value;

   Current_File : Unbounded_String;
   Line_No      : Natural := 0;

   procedure Fail (Msg : String) is
   begin
      raise Load_Error with To_String (Current_File) & ":"
        & Natural'Image (Line_No) & ": " & Msg;
   end Fail;

   function Int (L : Line_Info; Key : String; Default : Integer) return Integer
   is
      V : constant String := Value (L, Key);
   begin
      if V = "" then
         return Default;
      end if;
      return Integer'Value (V);
   exception
      when Constraint_Error =>
         Fail ("bad number for " & Key & ": " & V);
         return Default;
   end Int;

   function Int (S : String) return Integer is
   begin
      return Integer'Value (S);
   exception
      when Constraint_Error =>
         Fail ("bad number: " & S);
         return 0;
   end Int;

   --  Underscores in names become spaces.
   function Pretty (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C = '_' then
            C := ' ';
         end if;
      end loop;
      return R;
   end Pretty;

   function Strip_Comment (S : String) return String is
      P : constant Natural := Index (S, "#");
   begin
      --  '#' is also the trench terrain glyph; comments need "# " or
      --  must start the line.
      if P = S'First or else (P > 0 and then P < S'Last
                              and then S (P + 1) = ' ')
      then
         return S (S'First .. P - 1);
      end if;
      return S;
   end Strip_Comment;

   ---------------
   -- Era files --
   ---------------

   function Parse_Class (S : String) return Unit_Class is
   begin
      return Unit_Class'Value (S);
   exception
      when Constraint_Error =>
         Fail ("unknown unit class " & S);
         return Infantry;
   end Parse_Class;

   function Parse_Mover (S : String) return Move_Class is
   begin
      return Move_Class'Value (S);
   exception
      when Constraint_Error =>
         Fail ("unknown movement class " & S);
         return Foot;
   end Parse_Mover;

   procedure Load_Era (Id : String) is
      Path : constant String := Data_Dir & "/eras/" & To_Lower (Id) & ".era";
      F    : File_Type;
   begin
      if not Exists (Path) then
         Fail ("era file not found: " & Path);
      end if;
      Open (F, In_File, Path);
      Current_File := To_Unbounded_String (Path);
      Line_No := 0;
      while not End_Of_File (F) loop
         Line_No := Line_No + 1;
         declare
            L  : constant Line_Info := Split (Strip_Comment (Get_Line (F)));
            KW : constant String := To_String (L.Keyword);
         begin
            if KW = "era" then
               G.Era.Id   := To_Unbounded_String (To_Lower (Id));
               G.Era.Name := To_Unbounded_String
                 (Pretty (Value (L, "name", Id)));
            elsif KW = "rule" then
               G.Era.Max_Entrench := Int (L, "max_entrench",
                                          G.Era.Max_Entrench);
               G.Era.Charge_Bonus := Int (L, "charge_bonus",
                                          G.Era.Charge_Bonus);
               G.Era.Square_Bonus := Int (L, "square_bonus",
                                          G.Era.Square_Bonus);
               G.Era.Close_Armor_Penalty :=
                 Int (L, "close_armor_penalty", G.Era.Close_Armor_Penalty);
               G.Era.Supply_Range :=
                 Int (L, "supply_range", G.Era.Supply_Range);
            elsif KW = "unit" then
               declare
                  T : Unit_Type;
                  Flags : constant String := To_Lower (Value (L, "flags"));
               begin
                  T.Id   := To_Unbounded_String (Value (L, "id"));
                  if Length (T.Id) = 0 then
                     Fail ("unit without id");
                  end if;
                  T.Name := To_Unbounded_String
                    (Pretty (Value (L, "name", To_String (T.Id))));
                  T.Class  := Parse_Class (Value (L, "class", "infantry"));
                  T.Mover  := Parse_Mover (Value (L, "move", "foot"));
                  declare
                     Tg : constant String :=
                       To_Lower (Value (L, "target", "soft"));
                  begin
                     T.Target := (if Tg = "hard" then Hard
                                  elsif Tg = "air" then Air else Soft);
                  end;
                  T.Movement    := Int (L, "mp", 3);
                  T.Max_Range   := Int (L, "range", 1);
                  T.Soft_Attack := Int (L, "soft", 5);
                  T.Hard_Attack := Int (L, "hard", 1);
                  T.Defense     := Int (L, "def", 5);
                  T.Air_Attack  := Int (L, "air", 0);
                  T.Buyable     := To_Lower (Value (L, "buy", "yes")) /= "no"
                    and then T.Class /= Fortification;
                  T.Spot := Int
                    (L, "spot",
                     (case T.Class is
                         when Recon | Fighter | Bomber | Warship => 3,
                         when Cavalry => 3,
                         when others => 2));
                  T.Max_Ammo    := Int (L, "ammo", 8);
                  T.Max_Fuel    := Int (L, "fuel", 0);
                  T.Cost        := Int (L, "cost", 100);
                  T.Charge          := Index (Flags, "charge") > 0;
                  T.Support         := Index (Flags, "support") > 0;
                  T.Ignore_Entrench := Index (Flags, "sapper") > 0;
                  T.Bombard         := Index (Flags, "bombard") > 0;
                  if T.Mover = Static then
                     T.Movement := 0;
                  end if;
                  if T.Mover = Air then
                     T.Target := Air;
                  end if;
                  G.Types.Append (T);
               end;
            elsif KW /= "" then
               Fail ("unknown keyword " & KW);
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Load_Era;

   function Need_Type (Id : String) return Type_Index is
      T : constant Natural := Find_Type (Id);
   begin
      if T = 0 then
         Fail ("unknown unit type " & Id);
         return 1;
      end if;
      return T;
   end Need_Type;

   function Parse_Hex (S : String) return Hex is
      P : constant Natural := Index (S, ",");
   begin
      if P = 0 then
         Fail ("bad coordinate " & S);
      end if;
      return (Int (S (S'First .. P - 1)), Int (S (P + 1 .. S'Last)));
   end Parse_Hex;

   function Parse_Color (S : String) return RGB is
      P1 : constant Natural := Index (S, ",");
      P2 : constant Natural :=
        (if P1 = 0 then 0 else Index (S (P1 + 1 .. S'Last), ","));
   begin
      if P1 = 0 or else P2 = 0 then
         Fail ("bad colour " & S);
      end if;
      return (Float (Int (S (S'First .. P1 - 1))) / 255.0,
              Float (Int (S (P1 + 1 .. P2 - 1))) / 255.0,
              Float (Int (S (P2 + 1 .. S'Last))) / 255.0);
   end Parse_Color;

   -------------------
   -- Load_Scenario --
   -------------------

   procedure Load_Scenario (Path : String; Start : Boolean := True) is
      F : File_Type;
      Map_Rows_Left : Natural := 0;
      Map_Row       : Natural := 0;
      Scn_Name      : constant Unbounded_String := To_Unbounded_String (Path);
   begin
      Reset;
      Open (F, In_File, Path);
      G.Scenario_Path := Scn_Name;
      Current_File := Scn_Name;
      Line_No := 0;
      while not End_Of_File (F) loop
         declare
            Raw : constant String := Get_Line (F);
         begin
            Line_No := Line_No + 1;
            if Map_Rows_Left > 0 then
               --  A map row: one glyph per column, blanks ignored.
               declare
                  C : Natural := 0;
                  T : Terrain_Kind;
                  Ok : Boolean;
               begin
                  for Ch of Raw loop
                     if Ch not in ' ' | ASCII.HT | ASCII.CR then
                        From_Char (Ch, T, Ok);
                        if not Ok then
                           Fail ("unknown terrain glyph '" & Ch & "'");
                        end if;
                        if C < G.Cols then
                           G.Cells (C, Map_Row).Terrain := T;
                        end if;
                        C := C + 1;
                     end if;
                  end loop;
                  if C /= G.Cols then
                     Fail ("map row has" & Natural'Image (C)
                           & " columns, expected" & Natural'Image (G.Cols));
                  end if;
               end;
               Map_Row := Map_Row + 1;
               Map_Rows_Left := Map_Rows_Left - 1;
            else
               declare
                  L  : constant Line_Info := Split (Strip_Comment (Raw));
                  KW : constant String := To_String (L.Keyword);
               begin
                  if KW = "title" then
                     G.Title := L.Rest;
                  elsif KW = "description" then
                     if Length (G.Description) > 0 then
                        Append (G.Description, " ");
                     end if;
                     Append (G.Description, L.Rest);
                  elsif KW = "era" then
                     Load_Era (To_String (L.Tokens (1)));
                     Current_File := Scn_Name;
                  elsif KW = "category" then
                     G.Category := L.Rest;
                  elsif KW = "fog" then
                     G.Fog := To_Lower (To_String (L.Rest)) /= "off";
                  elsif KW = "buy" then
                     --  buy side=N types=a,b,c | none
                     declare
                        S : constant Player_Side :=
                          Player_Side (Int (L, "side", 1));
                        Ts : constant String := Value (L, "types");
                     begin
                        G.Sides (S).Buy_List := To_Unbounded_String
                          (if To_Lower (Ts) = "none" then "none"
                           else "," & Ts & ",");
                     end;
                  elsif KW = "hint" then
                     --  hint turn=N text...   |   hint event=name text...
                     declare
                        H     : Hint;
                        R     : constant String := To_String (L.Rest);
                        Sp    : constant Natural := Index (R, " ");
                        First : constant String :=
                          (if Sp = 0 then R else R (R'First .. Sp - 1));
                     begin
                        H.Turn  := Int (L, "turn", 0);
                        H.Event := To_Unbounded_String
                          (To_Lower (Value (L, "event")));
                        H.Text  := To_Unbounded_String
                          (if Sp = 0 then ""
                           else Trim (R (Sp + 1 .. R'Last), Ada.Strings.Both));
                        if Index (First, "=") = 0 then
                           Fail ("hint needs turn=N or event=name");
                        end if;
                        G.Hints.Append (H);
                     end;
                  elsif KW = "more" then
                     --  continuation line of the previous hint
                     if G.Hints.Is_Empty then
                        Fail ("'more' without a hint");
                     end if;
                     declare
                        H : Hint := G.Hints.Last_Element;
                     begin
                        Append (H.Text, ASCII.LF & To_String (L.Rest));
                        G.Hints.Replace_Element (G.Hints.Last_Index, H);
                     end;
                  elsif KW = "climate" then
                     --  climate fair|temperate|wet|winter
                     declare
                        C : constant String := To_Lower (To_String (L.Rest));
                     begin
                        G.Climate :=
                          (if C = "temperate" then Temperate
                           elsif C = "wet" then Wet
                           elsif C = "winter" then Winter
                           elsif C = "fair" then Always_Fair
                           else Always_Fair);
                        if C not in "fair" | "temperate" | "wet" | "winter"
                        then
                           Fail ("unknown climate " & C);
                        end if;
                     end;
                  elsif KW = "weather" then
                     --  weather turn=N fair|overcast|rain|snow|fog
                     declare
                        P : Planned_Weather;
                        K : constant String :=
                          (if L.Count >= 2
                           then To_Lower (To_String (L.Tokens (2))) else "");
                     begin
                        P.Turn := Int (L, "turn", 1);
                        if K = "fair" then
                           P.Kind := Fair;
                        elsif K = "overcast" then
                           P.Kind := Overcast;
                        elsif K = "rain" then
                           P.Kind := Rain;
                        elsif K = "snow" then
                           P.Kind := Snow;
                        elsif K = "fog" then
                           P.Kind := Mist;
                        else
                           Fail ("weather needs turn=N and a kind");
                        end if;
                        G.Weather_Plan.Append (P);
                     end;
                  elsif KW = "supply" then
                     --  supply side=N edge=west|east|north|south|none
                     declare
                        S : constant Player_Side :=
                          Player_Side (Int (L, "side", 1));
                        E : constant String := To_Lower (Value (L, "edge"));
                     begin
                        G.Supply_Edge (S) :=
                          (if E = "west" then West elsif E = "east" then East
                           elsif E = "north" then North
                           elsif E = "south" then South
                           elsif E = "none" then No_Edge else Auto);
                     end;
                  elsif KW = "turns" then
                     G.Max_Turns := Int (To_String (L.Tokens (1)));
                  elsif KW = "attacker" then
                     G.Attacker :=
                       Player_Side (Int (To_String (L.Tokens (1))));
                  elsif KW = "first" then
                     G.First := Player_Side (Int (To_String (L.Tokens (1))));
                  elsif KW = "side" then
                     declare
                        S : constant Player_Side :=
                          Player_Side (Int (To_String (L.Tokens (1))));
                        I : Side_Info renames G.Sides (S);
                     begin
                        I.Name := To_Unbounded_String
                          (Pretty (Value (L, "name", "Side")));
                        I.Color := Parse_Color
                          (Value (L, "color", "128,128,128"));
                        I.Control :=
                          (if To_Lower (Value (L, "control", "human")) = "ai"
                           then Computer else Human);
                        I.Prestige := Int (L, "prestige", 0);
                        I.Income   := Int (L, "income", 0);
                     end;
                  elsif KW = "map" then
                     G.Cols := Int (To_String (L.Tokens (1)));
                     G.Rows := Int (To_String (L.Tokens (2)));
                     if G.Cols not in 1 .. Max_Cols
                       or else G.Rows not in 1 .. Max_Rows
                     then
                        Fail ("map too large");
                     end if;
                     Map_Rows_Left := G.Rows;
                     Map_Row := 0;
                  elsif KW = "territory" then
                     --  territory side=N cols=A-B : owns capturable hexes
                     declare
                        S  : constant Side_Id := Side_Id (Int (L, "side", 0));
                        CS : constant String := Value (L, "cols", "0-0");
                        P  : constant Natural := Index (CS, "-");
                        A  : constant Integer := Int (CS (CS'First .. P - 1));
                        B  : constant Integer := Int (CS (P + 1 .. CS'Last));
                     begin
                        for C in A .. Integer'Min (B, G.Cols - 1) loop
                           for R in 0 .. G.Rows - 1 loop
                              if Is_Capturable (G.Cells (C, R).Terrain) then
                                 G.Cells (C, R).Owner := S;
                              end if;
                           end loop;
                        end loop;
                     end;
                  elsif KW = "place" then
                     declare
                        H : constant Hex := Parse_Hex (Value (L, "at"));
                     begin
                        if not In_Map (H) then
                           Fail ("place outside map");
                        end if;
                        declare
                           C : Cell renames G.Cells (H.Col, H.Row);
                        begin
                           C.Name := To_Unbounded_String
                             (Pretty (Value (L, "name")));
                           if Has_Key (L, "owner") then
                              C.Owner := Side_Id (Int (L, "owner", 0));
                           end if;
                           C.Victory := Has_Key (L, "victory");
                        end;
                     end;
                  elsif KW = "reinforce" then
                     --  reinforce turn=N side=S type=T at=c,r [core]
                     declare
                        R : Reinforcement;
                     begin
                        R.Turn := Int (L, "turn", 1);
                        R.Side := Player_Side (Int (L, "side", 1));
                        R.Kind := Need_Type (Value (L, "type"));
                        R.Pos  := Parse_Hex (Value (L, "at"));
                        R.Core := Has_Key (L, "core");
                        if not In_Map (R.Pos) then
                           Fail ("reinforcement outside map");
                        end if;
                        G.Reinforcements.Append (R);
                     end;
                  elsif KW = "unit" then
                     declare
                        U : Unit;
                     begin
                        U.Side := Player_Side (Int (L, "side", 1));
                        U.Kind := Need_Type (Value (L, "type"));
                        U.Core := Has_Key (L, "core");
                        U.Pos  := Parse_Hex (Value (L, "at"));
                        U.Strength   := Int (L, "str", Max_Strength);
                        U.Experience := Int (L, "exp", 0);
                        U.Entrench   := Int (L, "entrench", 0);
                        if not In_Map (U.Pos) then
                           Fail ("unit outside map at " & Image (U.Pos));
                        elsif not Is_Air (G.Types (U.Kind))
                          and then Unit_At (U.Pos) /= No_Unit
                        then
                           Fail ("two units at " & Image (U.Pos));
                        elsif Air_At (U.Pos) /= No_Unit then
                           Fail ("two aircraft at " & Image (U.Pos));
                        elsif Move_Cost (Terrain_At (U.Pos),
                                         G.Types (U.Kind).Mover) = Impassable
                          and then G.Types (U.Kind).Mover /= Static
                        then
                           Fail ("unit in water at " & Image (U.Pos));
                        end if;
                        Add_Unit (U);
                     end;
                  elsif KW /= "" then
                     Fail ("unknown keyword " & KW);
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
      if Map_Rows_Left > 0 then
         raise Load_Error with Path & ": map has too few rows";
      end if;
      if G.Units.Is_Empty then
         raise Load_Error with Path & ": no units";
      end if;
      Resolve_Supply_Edges;
      if Start then
         Start_Game;
      else
         G.Loaded := True;
      end if;
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
         raise Load_Error with "cannot open " & Path;
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Load_Scenario;

   ------------------
   -- Read_Preview --
   ------------------

   procedure Read_Preview (Path : String; P : out Preview_Data) is
      F        : File_Type;
      Map_Left : Natural := 0;
      Row      : Natural := 0;
   begin
      P := (others => <>);
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         declare
            Raw : constant String := Get_Line (F);
         begin
            if Map_Left > 0 then
               declare
                  C : Natural := 0;
               begin
                  for Ch of Raw loop
                     if Ch not in ' ' | ASCII.HT | ASCII.CR
                       and then C < P.Cols and then C <= 59 and then Row <= 39
                     then
                        P.Glyphs (C, Row) := Ch;
                        C := C + 1;
                     end if;
                  end loop;
               end;
               Row := Row + 1;
               Map_Left := Map_Left - 1;
            else
               declare
                  L  : constant Line_Info := Split (Strip_Comment (Raw));
                  KW : constant String := To_String (L.Keyword);

                  function Coord (S : String; Second : Boolean)
                                  return Integer is
                     Comma : constant Natural := Index (S, ",");
                  begin
                     if Comma = 0 then
                        return -1;
                     end if;
                     return Integer'Value
                       (if Second then S (Comma + 1 .. S'Last)
                        else S (S'First .. Comma - 1));
                  exception
                     when Constraint_Error =>
                        return -1;
                  end Coord;
               begin
                  if KW = "map" and then L.Count >= 2 then
                     P.Cols := Natural'Min
                       (60, Natural'Value (To_String (L.Tokens (1))));
                     P.Rows := Natural'Min
                       (40, Natural'Value (To_String (L.Tokens (2))));
                     Map_Left := P.Rows;
                     Row := 0;
                  elsif KW = "turns" and then L.Count >= 1 then
                     P.Turns := Natural'Value (To_String (L.Tokens (1)));
                  elsif KW = "side" and then L.Count >= 1 then
                     declare
                        S : constant Integer :=
                          Integer'Value (To_String (L.Tokens (1)));
                     begin
                        if S in 1 .. 2 then
                           P.Colors (Player_Side (S)) :=
                             To_Unbounded_String
                               (Value (L, "color", "128,128,128"));
                           P.Names (Player_Side (S)) :=
                             To_Unbounded_String
                               (Pretty (Value (L, "name", "Side")));
                        end if;
                     end;
                  elsif KW = "territory" then
                     declare
                        S  : constant Integer := Int (L, "side", 0);
                        CS : constant String := Value (L, "cols", "0-0");
                        D  : constant Natural := Index (CS, "-");
                     begin
                        if D > 0 and then S in 0 .. 2 then
                           for C in Integer'Value (CS (CS'First .. D - 1))
                             .. Integer'Min
                               (Integer'Value (CS (D + 1 .. CS'Last)),
                                P.Cols - 1)
                           loop
                              for R in 0 .. P.Rows - 1 loop
                                 if P.Glyphs (C, R) in 't' | 'C' | 'F' | 'A'
                                 then
                                    P.Owner (C, R) := Side_Id (S);
                                 end if;
                              end loop;
                           end loop;
                        end if;
                     end;
                  elsif KW = "place" then
                     declare
                        A : constant String := Value (L, "at");
                        C : constant Integer := Coord (A, False);
                        R : constant Integer := Coord (A, True);
                     begin
                        if C in 0 .. P.Cols - 1 and then R in 0 .. P.Rows - 1
                        then
                           if Has_Key (L, "owner") then
                              P.Owner (C, R) :=
                                Side_Id (Integer'Max
                                           (0, Integer'Min
                                              (2, Int (L, "owner", 0))));
                           end if;
                           P.Victory (C, R) := Has_Key (L, "victory");
                        end if;
                     end;
                  elsif KW = "unit" and then P.Unit_Count < Preview_Max_Units
                  then
                     declare
                        A : constant String := Value (L, "at");
                        S : constant Integer := Int (L, "side", 1);
                     begin
                        if S in 1 .. 2 then
                           P.Unit_Count := P.Unit_Count + 1;
                           P.Units (P.Unit_Count) :=
                             (Coord (A, False), Coord (A, True),
                              Player_Side (S));
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
      P.Ok := P.Cols > 0 and then P.Rows > 0;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         P.Ok := False;
   end Read_Preview;

   --------------------
   -- List_Scenarios --
   --------------------

   function List_Scenarios return Info_Vectors.Vector is
      Result : Info_Vectors.Vector;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
      Dir    : constant String := Data_Dir & "/scenarios";
   begin
      if not Exists (Dir) then
         return Result;
      end if;
      Start_Search (Search, Dir, "*.scn");
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Info : Scenario_Info;
            F    : File_Type;
         begin
            Info.Path := To_Unbounded_String (Full_Name (Item));
            Info.Preview := Info.Path;
            Info.Title := To_Unbounded_String (Simple_Name (Item));
            Open (F, In_File, Full_Name (Item));
            while not End_Of_File (F) loop
               declare
                  L  : constant Line_Info := Split (Get_Line (F));
                  KW : constant String := To_String (L.Keyword);
               begin
                  if KW = "title" then
                     Info.Title := L.Rest;
                  elsif KW = "category" then
                     Info.Category := L.Rest;
                  elsif KW = "era" then
                     Info.Era := To_Unbounded_String
                       (To_Upper (To_String (L.Tokens (1))));
                  elsif KW = "description" then
                     if Length (Info.Description) > 0 then
                        Append (Info.Description, " ");
                     end if;
                     Append (Info.Description, L.Rest);
                  elsif KW = "map" then
                     exit;
                  end if;
               end;
            end loop;
            Close (F);
            Result.Append (Info);
         end;
      end loop;
      End_Search (Search);

      --  Sort by era then title.
      declare
         type Arr is array (Positive range <>) of Scenario_Info;
         function Key (A : Scenario_Info) return String is
           ((if Length (A.Category) > 0 then "0" else "1")
            & To_String (A.Era) & "|" & To_String (A.Title));
         function "<" (A, B : Scenario_Info) return Boolean is
           (Key (A) < Key (B));
         procedure Sort is new Ada.Containers.Generic_Array_Sort
           (Positive, Scenario_Info, Arr);
         A : Arr (1 .. Natural (Result.Length));
      begin
         for I in A'Range loop
            A (I) := Result (I);
         end loop;
         Sort (A);
         Result.Clear;
         for X of A loop
            Result.Append (X);
         end loop;
      end;
      return Result;
   end List_Scenarios;

end Engine.Loader;
