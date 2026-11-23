-- ***************************************************************************
--                      Hexfront - Selftest
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

--  Headless engine check: plays every scenario AI-vs-AI and reports,
--  then exercises save/load and a full campaign.
with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Engine;                 use Engine;
with Engine.Game;            use Engine.Game;
with Engine.Loader;          use Engine.Loader;
with Engine.AI;
with Engine.Save;
with Engine.Campaign;
with Engine.Editing;
with Engine.Terrain;
with Engine.Units;
with Engine.Hexes;              use type Engine.Hexes.Hex;

procedure Selftest is
   Verbose : constant Boolean :=
     Argument_Count > 0 and then Argument (1) = "-v";
   Supply_Stats : constant Boolean :=
     Argument_Count > 0 and then Argument (1) = "-s";
   Rounds  : constant Positive :=
     (if Argument_Count > 0 and then Argument (1) (1) /= '-'
      then Positive'Value (Argument (1)) else 1);
   --  Unit-turns spent in each supply state, per side ("-s").
   Supply_Count : array (Player_Side, Supply_Level) of Natural :=
     (others => (others => 0));

   procedure Play_Turn is
   begin
      Engine.AI.Begin_Turn;
      while Engine.AI.Step loop
         null;
      end loop;
      End_Turn;
   end Play_Turn;

   procedure Play_Out is
   begin
      G.Sides (1).Control := Computer;
      G.Sides (2).Control := Computer;
      while G.Winner = 0 loop
         Play_Turn;
         if Supply_Stats then
            for I in G.Units.First_Index .. G.Units.Last_Index loop
               if G.Units (I).Alive then
                  Supply_Count (G.Units (I).Side, Supply_Of (I)) :=
                    Supply_Count (G.Units (I).Side, Supply_Of (I)) + 1;
               end if;
            end loop;
         end if;
      end loop;
   end Play_Out;

   function Alive (S : Player_Side) return Natural is
      N : Natural := 0;
   begin
      for U of G.Units loop
         if U.Alive and then U.Side = S then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Alive;

   Wins : array (1 .. 40, Player_Side) of Natural :=
     (others => (others => 0));
   Att_Wins : array (1 .. 40) of Natural := (others => 0);
   Played   : array (1 .. 40) of Boolean := (others => False);
   List : constant Info_Vectors.Vector := List_Scenarios;
begin
   Record_Effects := False;
   for R in 1 .. Rounds loop
      for I in List.First_Index .. List.Last_Index loop
         --  HEXFRONT_ONLY=<file name part> restricts the scenario runs.
         if Ada.Environment_Variables.Exists ("HEXFRONT_ONLY")
           and then Ada.Strings.Fixed.Index
             (To_String (List (I).Path),
              Ada.Environment_Variables.Value ("HEXFRONT_ONLY")) = 0
         then
            goto Skip;
         end if;
         Load_Scenario (To_String (List (I).Path));
         Play_Out;
         Wins (I, G.Winner) := Wins (I, G.Winner) + 1;
         if G.Winner = G.Attacker then
            Att_Wins (I) := Att_Wins (I) + 1;
         end if;
         Played (I) := True;
         if Verbose then
            for M of Messages loop
               Put_Line ("   " & M);
            end loop;
         end if;
         Messages.Clear;
         if Supply_Stats then
            Put ("   supply (ok/low/cut) edges " & Edge_Name (G.Supply_Edge (1))
                 & "/" & Edge_Name (G.Supply_Edge (2)) & ":");
            for S in Player_Side loop
               for L in Supply_Level loop
                  Put (Supply_Count (S, L)'Image);
               end loop;
               Put (" |");
            end loop;
            New_Line;
            Supply_Count := (others => (others => 0));
         end if;
         if Rounds = 1 then
            Put_Line (To_String (List (I).Title) & ": "
                      & To_String (G.Sides (G.Winner).Name)
                      & " wins on turn" & G.Turn'Image & ", objectives"
                      & Victory_Hexes_Owned (G.Attacker)'Image & " /"
                      & Victory_Hexes_Total'Image & ", units left"
                      & Alive (1)'Image & " vs" & Alive (2)'Image);
         end if;
         <<Skip>>
      end loop;
   end loop;
   if Rounds > 1 then
      for I in List.First_Index .. List.Last_Index loop
         if Played (I) then
            Put_Line (To_String (List (I).Title) & ": attacker won"
                      & Att_Wins (I)'Image & " of" & Rounds'Image);
         end if;
      end loop;
   end if;

   --  Undo: a quiet move can be taken back exactly.
   declare
      R      : Reach_Map;
      Before : Engine.Units.Unit;
      Target : Engine.Hexes.Hex := Engine.Hexes.No_Hex;
   begin
      Load_Scenario (To_String (List.First_Element.Path));
      G.Sides (1).Control := Human;
      G.Sides (2).Control := Computer;
      Before := G.Units (1);
      Compute_Reach (1, R);
      for C in 0 .. G.Cols - 1 loop
         for Rw in 0 .. G.Rows - 1 loop
            if Target = Engine.Hexes.No_Hex and then Can_Move_To (1, R, (C, Rw))
              and then R.Cost (C, Rw) = 1
            then
               Target := (C, Rw);
            end if;
         end loop;
      end loop;
      Move_Unit_Undoable (1, Target, R);
      declare
         Could : constant Boolean := Can_Undo;
      begin
         Undo_Move;
         Put_Line ("undo: possible=" & Could'Image & ", restored="
                   & Boolean'Image (G.Units (1).Pos = Before.Pos
                                    and then G.Units (1).Moves_Left
                                             = Before.Moves_Left
                                    and then Unit_At (Before.Pos) = 1));
      end;
   end;

   --  Reinforcements arrive.
   declare
      Arrivals : Natural := 0;
   begin
      for Info of List loop
         Load_Scenario (To_String (Info.Path));
         Play_Out;
         for R of G.Reinforcements loop
            if R.Done then
               Arrivals := Arrivals + 1;
            end if;
         end loop;
      end loop;
      Put_Line ("reinforcements arrived:" & Arrivals'Image);
   end;

   --  Save / load round trip.
   declare
      Path : constant String := "/tmp/hexfront_selftest.sav";
      N1, N2 : Natural;
   begin
      Load_Scenario (To_String (List.First_Element.Path));
      G.Sides (1).Control := Computer;
      G.Sides (2).Control := Computer;
      for K in 1 .. 4 loop
         Play_Turn;
      end loop;
      N1 := Alive (1) + Alive (2);
      Engine.Save.Save_Game (Path);
      Engine.Save.Load_Game (Path);
      N2 := Alive (1) + Alive (2);
      Put_Line ("save/load: units" & N1'Image & " ->" & N2'Image
                & ", turn" & G.Turn'Image
                & (if N1 = N2 then "  OK" else "  MISMATCH"));
      Play_Out;
   end;

   --  Editor round trip: every scenario written back out must load again
   --  with the same number of units.
   for Info of List loop
      declare
         Path : constant String := "/tmp/hexfront_rt.scn";
         N1, N2 : Natural;
      begin
         Load_Scenario (To_String (Info.Path), Start => False);
         N1 := Alive (1) + Alive (2);
         Engine.Editing.Write_Scenario (Path);
         Load_Scenario (Path, Start => False);
         N2 := Alive (1) + Alive (2);
         if N1 /= N2 then
            Put_Line ("editor round trip MISMATCH: " & To_String (Info.Title));
         end if;
      end;
   end loop;
   Put_Line ("editor round trip: done");

   --  Build a scenario from scratch with the editor operations.
   declare
      use Engine.Editing;
      Path : constant String := "/tmp/hexfront_new.scn";
   begin
      New_Map ("napoleonic", 12, 8);
      for C in 0 .. 11 loop
         Paint ((C, 4), Engine.Terrain.Road);
      end loop;
      Paint ((9, 4), Engine.Terrain.Town);
      Set_Place ((9, 4), "Testburg", 2, True);
      Put_Unit ((1, 3), 1, Find_Type ("line"));
      Put_Unit ((1, 5), 1, Find_Type ("cuirass"));
      Put_Unit ((2, 4), 1, Find_Type ("footart"));
      Put_Unit ((9, 4), 2, Find_Type ("line"));
      Put_Unit ((9, 4), 2, Find_Type ("grenadier"));   --  replaces line
      Put_Line ("editor validate: '" & Validate & "'");
      Write_Scenario (Path);
      Load_Scenario (Path);
      Put_Line ("editor scenario: " & To_String (G.Title) & ", units"
                & Natural'Image (Alive (1) + Alive (2)));
      Play_Out;
      Put_Line ("editor scenario played: winner "
                & To_String (G.Sides (G.Winner).Name));
   end;

   --  Campaign run.
   declare
      Report : Unbounded_String;
      Camps  : constant Info_Vectors.Vector :=
        Engine.Campaign.List_Campaigns;
   begin
      for Cp of Camps loop
         Put_Line ("campaign: " & To_String (Cp.Title));
         Engine.Campaign.Load_Campaign (To_String (Cp.Path));
         loop
            Engine.Campaign.Start_Stage;
            Put_Line ("  stage " & To_String (G.Title) & ": side 1 has"
                      & Alive (1)'Image & " units, prestige"
                      & G.Sides (1).Prestige'Image);
            Play_Out;
            exit when not Engine.Campaign.Finish_Stage (Report);
            --  Spend prestige on the first possible upgrades.
            declare
               use Engine.Campaign;
               Done : Natural := 0;
            begin
               for K in 1 .. Natural (C.Carried.Length) loop
                  for T in G.Types.First_Index .. G.Types.Last_Index loop
                     if Can_Upgrade (K, T)
                       and then G.Types (T).Cost
                         > G.Types (Find_Type
                                      (To_String (C.Carried (K).Type_Id))).Cost
                     then
                        Upgrade (K, T);
                        Done := Done + 1;
                        exit;
                     end if;
                  end loop;
               end loop;
               Put_Line ("  upgrades bought:" & Done'Image
                         & ", prestige left" & C.Prestige'Image);
            end;
         end loop;
         Put_Line ("  " & To_String (Report));
      end loop;
   end;
end Selftest;
